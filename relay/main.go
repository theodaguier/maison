// Maison's relay: holds the credentials that can't ship in the app and forwards requests. It stores
// nothing: no meter id, no reading, no consent. The only state is the operator's access token, in memory.
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	config, err := loadConfig(os.Getenv)
	if err != nil {
		log.Fatalf("configuration: %v", err)
	}
	server := &http.Server{
		Addr:              ":" + config.port,
		Handler:           newRouter(config, http.DefaultClient),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		log.Printf("relay listening on :%s", config.port)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("listen: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = server.Shutdown(ctx)
}

// newRouter wires the routes. `client` reaches the operators; tests pass a fake.
func newRouter(config Config, client *http.Client) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	enedis := newEnedis(config, client)
	mux.HandleFunc("GET /enedis/authorize", enedis.authorize)
	mux.HandleFunc("GET /enedis/callback", enedis.callback)
	mux.HandleFunc("GET /enedis/consumption_load_curve", enedis.meteringData("/metering_data_clc/v5/consumption_load_curve"))
	mux.HandleFunc("GET /enedis/daily_consumption", enedis.meteringData("/metering_data_dc/v5/daily_consumption"))
	return logRequests(mux)
}

// logRequests logs the route and the status, never the query: it carries meter ids.
func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		start := time.Now()
		next.ServeHTTP(recorder, r)
		log.Printf("%s %s %d %s", r.Method, r.URL.Path, recorder.status, time.Since(start).Round(time.Millisecond))
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}
