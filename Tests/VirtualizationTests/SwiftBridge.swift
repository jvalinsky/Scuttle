import Foundation
import Containerization
import ContainerizationOCI
import ContainerizationEXT4
import NIOCore
import NIOPosix

@objc public class SRLinuxTestRunner: NSObject {
    
    @objc public override init() {
        super.init()
    }

    // Helper to capture stdout/stderr output
    final class BufferWriter: Writer {
        var data = Data()
        func write(_ data: Data) throws {
            self.data.append(data)
        }
        func close() throws {}
    }

    @objc public func runCommand(_ command: String, image imageReference: String, completion: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                let output = try await executeInContainer(command: command, imageReference: imageReference)
                completion(true, output)
            } catch {
                completion(false, error.localizedDescription)
            }
        }
    }
    
    private func executeInContainer(command: String, imageReference: String) async throws -> String {
        // 1. Resolve Paths from Environment or Defaults
        // To run Virtualization, we need a Linux kernel and initial filesystem block.
        let kernelPath = ProcessInfo.processInfo.environment["LINUX_KERNEL"] ?? "/usr/local/bin/vmlinux"
        let initfsPath = ProcessInfo.processInfo.environment["LINUX_INITFS"] ?? "/usr/local/bin/init.block"
        
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appRoot = appSupport.appendingPathComponent("com.scuttle.containerization")
        try fileManager.createDirectory(at: appRoot, withIntermediateDirectories: true)
        
        // 2. Setup Stores
        let contentStore = try LocalContentStore(path: appRoot.appendingPathComponent("content"))
        let imageStore = try ImageStore(path: appRoot, contentStore: contentStore)
        
        // 3. Fetch/Pull Image
        let image: Containerization.Image
        do {
            image = try await imageStore.get(reference: imageReference)
        } catch {
            image = try await imageStore.pull(reference: imageReference)
        }
        
        // 4. Unpack Image to EXT4 Disk
        // Assuming Apple Silicon (arm64) for local development
        let platform = Platform(arch: "arm64", os: "linux", variant: "v8")
        let fsPath = appRoot.appendingPathComponent("\(image.digest).ext4")
        
        // Unpack if not already present
        if !fileManager.fileExists(atPath: fsPath.path) {
            let unpacker = EXT4Unpacker(blockSizeInBytes: 2 * 1024 * 1024 * 1024) // 2GB
            _ = try await unpacker.unpack(image, for: platform, at: fsPath)
        }
        
        let rootfsMount = Mount.block(
            format: "ext4",
            source: fsPath.path,
            destination: "/",
            options: []
        )
        
        // 5. Setup VM Manager
        let kernel = Kernel(path: URL(fileURLWithPath: kernelPath), platform: .linuxArm)
        let initfs = Mount.block(
            format: "ext4",
            source: initfsPath,
            destination: "/",
            options: ["ro"]
        )
        let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        
        let vmm = VZVirtualMachineManager(
            kernel: kernel,
            initialFilesystem: initfs,
            group: eventLoop
        )
        
        // 6. Create and Start Container
        let buffer = BufferWriter()
        let containerID = "scuttle-test-\(UUID().uuidString.prefix(8))"
        let container = try LinuxContainer(containerID, rootfs: rootfsMount, vmm: vmm) { config in
            config.process.arguments = ["sh", "-c", command]
            config.process.stdout = buffer
            
            // Mount the workspace root (Scuttle source code)
            let workspaceHostPath = NSHomeDirectory() + "/Software/Scuttle" // Adjust if needed
            config.mounts.append(.share(source: workspaceHostPath, destination: "/workspace"))
        }
        
        try await container.create()
        try await container.start()
        _ = try await container.wait()
        try await container.stop()
        
        return String(data: buffer.data, encoding: .utf8) ?? ""
    }
}
