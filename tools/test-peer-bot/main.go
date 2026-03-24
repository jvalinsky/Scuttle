package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"
)

type ControlServer struct {
	bot    *Bot
	server *http.Server
	mu     sync.Mutex
	status string
}

func main() {
	dataDir := os.Getenv("SSB_DATA_DIR")
	if dataDir == "" {
		dataDir = "./ssb-room-data"
	}

	bot, err := NewBot(dataDir)
	if err != nil {
		log.Fatalf("Failed to create bot: %v", err)
	}
	defer bot.Close()

	log.Printf("Bot initialized with peer ID: %s", bot.GetPeerID())

	server := &ControlServer{
		bot:    bot,
		status: "idle",
	}

	http.HandleFunc("/start", server.handleStart)
	http.HandleFunc("/stop", server.handleStop)
	http.HandleFunc("/status", server.handleStatus)

	addr := ":9999"
	log.Printf("Control server listening on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

func (s *ControlServer) handleStart(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	messages := 10
	if n := r.URL.Query().Get("messages"); n != "" {
		if m, err := strconv.Atoi(n); err == nil && m > 0 {
			messages = m
		}
	}

	s.mu.Lock()
	s.status = "starting"
	s.mu.Unlock()

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()

		log.Printf("Publishing %d test messages...", messages)
		if err := s.bot.PublishTestMessages(ctx, messages); err != nil {
			log.Printf("Failed to publish messages: %v", err)
			s.mu.Lock()
			s.status = "error"
			s.mu.Unlock()
			return
		}

		s.mu.Lock()
		s.status = "ready"
		s.mu.Unlock()
		log.Printf("Published %d messages successfully", messages)
	}()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "started", "messages": strconv.Itoa(messages)})
}

func (s *ControlServer) handleStop(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	s.mu.Lock()
	s.status = "stopped"
	s.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "stopped"})
}

func (s *ControlServer) handleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	s.mu.Lock()
	status := s.status
	s.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  status,
		"peer_id": s.bot.GetPeerID(),
	})
}
