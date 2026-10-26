package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthCheckAnswersAndNothingElseIsServed(t *testing.T) {
	router := newRouter()
	for path, want := range map[string]int{"/healthz": http.StatusNoContent, "/anything-else": http.StatusNotFound} {
		recorder := httptest.NewRecorder()
		router.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, path, nil))
		if recorder.Code != want {
			t.Errorf("GET %s: %d, want %d", path, recorder.Code, want)
		}
	}
}

func TestPortDefaultsTo8080(t *testing.T) {
	config, err := loadConfig(func(string) string { return "" })
	if err != nil || config.port != "8080" {
		t.Fatalf("got %+v, %v", config, err)
	}
	config, _ = loadConfig(func(key string) string {
		if key == "PORT" {
			return "9000"
		}
		return ""
	})
	if config.port != "9000" {
		t.Fatalf("PORT ignored: %+v", config)
	}
}
