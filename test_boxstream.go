package main

import (
	"crypto/rand"
	"fmt"

	"golang.org/x/crypto/nacl/secretbox"
)

func main() {
	key := [32]byte{}
	rand.Read(key[:])

	nonce1 := [24]byte{}
	nonce2 := [24]byte{}
	nonce2[23] = 1 // Simplified increment

	msg := []byte("Hello MuxRPC!")

	// encrypt body to get body mac
	bodyBox := secretbox.Seal(nil, msg, &nonce2, &key)
	bodyMAC := bodyBox[:16]
	bodyCipher := bodyBox[16:]

	// encrypt header
	headerPlain := make([]byte, 18)
	headerPlain[0] = byte(len(msg) >> 8)
	headerPlain[1] = byte(len(msg))
	copy(headerPlain[2:], bodyMAC)

	headerBox := secretbox.Seal(nil, headerPlain, &nonce1, &key)

	fmt.Printf("headerBox len: %d\n", len(headerBox))
	fmt.Printf("bodyCipher len: %d\n", len(bodyCipher))
}
