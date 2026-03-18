# Atomic Patterns

## Using _Atomic (C11)

For simple scalar values, `_Atomic` provides lock-free thread safety:

```objc
@property (nonatomic, assign) _Atomic int32_t counter;

// Increment - thread-safe, lock-free
int32_t oldValue = atomic_fetch_add_explicit(&_counter, 1, memory_order_relaxed);

// Decrement
atomic_fetch_sub_explicit(&_counter, 1, memory_order_relaxed);

// Read
int32_t current = atomic_load_explicit(&_counter, memory_order_relaxed);
```

## Memory Ordering

### memory_order_relaxed
- No ordering guarantees
- Only atomicity guaranteed
- Use for: simple counters where order doesn't matter

```objc
// Good: simple counter increment
atomic_fetch_add_explicit(&_counter, 1, memory_order_relaxed);
```

### memory_order_seq_cst (Default)
- Sequential consistency (strongest)
- Use for: when you need full ordering

```objc
// Good: flag that controls logic
atomic_store_explicit(&_flag, 1, memory_order_seq_cst);
```

## Objective-C @property atomic

### IMPORTANT: @property atomic does NOT mean thread-safe!

```objc
// WRONG: atomic does NOT guarantee thread safety
@property (atomic) NSMutableDictionary *dict;

// Thread 1
[self.dict setObject:@1 forKey:@"a"];  // May crash!

// Thread 2  
[self.dict setObject:@2 forKey:@"b"];  // Race condition!
```

### What atomic DOES do
- Generates lock/unlock code for getter/setter
- Prevents partial reads/writes
- Does NOT prevent concurrent access

## Scuttle Usage

### Good: SSBMuxRPCSession

```objc
// Sources/SSBMuxRPCSession.m line 10-11
@property (nonatomic, assign) _Atomic int32_t nextRequestID;
@property (nonatomic, strong) dispatch_queue_t accessQueue;

// Line 36 - Atomic counter for request IDs
int32_t reqNum = atomic_fetch_add_explicit(&_nextRequestID, 1, memory_order_relaxed);
```

This is correct because:
1. Counter is simple int32_t - perfect for _Atomic
2. Queue protects the dictionary access separately
3. Request IDs only need to be unique, not ordered

## When to Use What

| Scenario | Solution |
|----------|----------|
| Simple counter (int, NSInteger) | _Atomic |
| Boolean flag | _Atomic bool |
| Object reference | Serial queue |
| Multiple related values | Serial queue |
| Read-heavy, write-light | Concurrent queue + barrier |

## Common Mistakes

### Mistake 1: Thinking atomic Property is Thread-Safe

```objc
// WRONG
@property (atomic, strong) NSArray *items;

// Still not thread-safe!
[items enumerateObjectsUsingBlock:...];  // Can crash if modified
```

### Mistake 2: Using _Atomic on Objects

```objc
// WRONG - _Atomic only works for scalar types
_Atomic NSObject *object;  // Undefined behavior!
```

### Mistake 3: Non-Atomic Compound Operations

```objc
// WRONG - two operations, not atomic together
int current = self.counter;  // Read
self.counter = current + 1;  // Write - race window in between!
```

### Correct: Use fetch_add

```objc
// CORRECT - single atomic operation
int old = atomic_fetch_add(&_counter, 1);  // Read-modify-write in one go
```
