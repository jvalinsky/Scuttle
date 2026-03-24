package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/pkg/errors"
	refs "github.com/ssbc/go-ssb-refs"
	"github.com/ssbc/go-ssb/sbot"
)

type Bot struct {
	sbot     *sbot.Sbot
	identity refs.FeedRef
	logFile  *os.File
	mu       sync.Mutex
}

func NewBot(dataDir string) (*Bot, error) {
	if err := os.MkdirAll(dataDir, 0700); err != nil {
		return nil, errors.Wrap(err, "failed to create data dir")
	}

	s, err := sbot.New(
		sbot.WithRepoPath(dataDir),
		sbot.WithListenAddr(":0"),
	)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize sbot")
	}

	logPath := filepath.Join(dataDir, "test-peer-bot.log")
	f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		s.Close()
		return nil, errors.Wrap(err, "failed to open log file")
	}

	return &Bot{
		sbot:     s,
		identity: s.KeyPair.ID(),
		logFile:  f,
	}, nil
}

func (b *Bot) LogEvent(event string, data map[string]interface{}) {
	b.mu.Lock()
	defer b.mu.Unlock()

	entry := make(map[string]interface{})
	for k, v := range data {
		entry[k] = v
	}
	entry["event"] = event
	entry["t"] = time.Now().Unix()

	json.NewEncoder(b.logFile).Encode(entry)
}

func (b *Bot) ConnectToRoom(ctx context.Context, addr string) error {
	networkAddr, err := net.ResolveTCPAddr("tcp", addr)
	if err != nil {
		b.LogEvent("connection_failed", map[string]interface{}{"error": err.Error(), "addr": addr})
		return errors.Wrap(err, "failed to resolve address")
	}

	err = b.sbot.Network.Connect(ctx, networkAddr)
	if err != nil {
		b.LogEvent("connection_failed", map[string]interface{}{"error": err.Error(), "addr": addr})
		return errors.Wrap(err, "failed to connect to room")
	}
	b.LogEvent("connected", map[string]interface{}{"addr": addr})
	return nil
}

func (b *Bot) PublishTestMessages(ctx context.Context, count int) error {
	for i := 0; i < count; i++ {
		content := map[string]interface{}{
			"type": "test",
			"text": fmt.Sprintf("Test message %d from Go bot", i),
			"seq":  i,
		}
		msg, err := b.sbot.PublishLog.Publish(content)
		if err != nil {
			b.LogEvent("publish_failed", map[string]interface{}{"error": err.Error(), "seq": i})
			return errors.Wrap(err, "failed to publish message")
		}
		b.LogEvent("published", map[string]interface{}{"ref": msg.Key().String(), "seq": i})
	}
	return nil
}

func (b *Bot) GetPeerID() string {
	return b.identity.String()
}

func (b *Bot) Close() {
	if b.sbot != nil {
		b.sbot.Close()
	}
	if b.logFile != nil {
		b.logFile.Close()
	}
}
