package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"
)

var (
	// A PRM: Enedis's 14-digit meter id.
	meterPattern = regexp.MustCompile(`^[0-9]{14}$`)
	statePattern = regexp.MustCompile(`^[A-Za-z0-9_-]{8,128}$`)
	dayPattern   = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}$`)
)

// Readings are a few hundred kilobytes at most; anything larger is not Enedis.
const maxBody = 5 << 20

type enedis struct {
	config Config
	client *http.Client

	mu          sync.Mutex
	token       string
	tokenExpiry time.Time
}

func newEnedis(config Config, client *http.Client) *enedis {
	return &enedis{config: config, client: client}
}

// authorize sends the person to Enedis's consent page. The state comes back unchanged, so the app
// knows the answer is to its own request.
func (e *enedis) authorize(w http.ResponseWriter, r *http.Request) {
	state := r.URL.Query().Get("state")
	if !statePattern.MatchString(state) {
		http.Error(w, "invalid state", http.StatusBadRequest)
		return
	}
	target, _ := url.Parse(e.config.enedisAuthorizeURL)
	query := target.Query()
	query.Set("client_id", e.config.enedisClientID)
	query.Set("state", state)
	query.Set("duration", e.config.enedisDuration)
	query.Set("response_type", "code")
	target.RawQuery = query.Encode()
	http.Redirect(w, r, target.String(), http.StatusFound)
}

// callback is Enedis's redirect after the consent. It hands the app the meter id and a key signed for
// that meter alone: the data routes ask for it, so knowing someone's meter id (it is on every bill) is
// not enough to read their consumption.
func (e *enedis) callback(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()
	state := query.Get("state")
	if !statePattern.MatchString(state) {
		http.Error(w, "invalid state", http.StatusBadRequest)
		return
	}
	answer := url.Values{"state": {state}}
	if refusal := query.Get("error"); refusal != "" {
		answer.Set("error", refusal)
	} else if meter := query.Get("usage_point_id"); meterPattern.MatchString(meter) {
		answer.Set("usage_point_id", meter)
		answer.Set("access", e.accessKey(meter))
	} else {
		answer.Set("error", "invalid_usage_point")
	}
	http.Redirect(w, r, strings.TrimSuffix(e.config.appCallback, "/")+"/enedis?"+answer.Encode(), http.StatusFound)
}

// accessKey is HMAC-SHA256(signing key, "enedis:" + meter), URL-safe. Nothing is stored: the relay
// recomputes it on each request.
func (e *enedis) accessKey(meter string) string {
	mac := hmac.New(sha256.New, e.config.signingKey)
	mac.Write([]byte("enedis:" + meter))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

// meteringData forwards a reading request for one meter and day range, and returns Enedis's answer
// unchanged: its status (the app reads a missing load curve from it) and its JSON.
func (e *enedis) meteringData(path string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		query := r.URL.Query()
		meter, start, end := query.Get("usage_point_id"), query.Get("start"), query.Get("end")
		if !meterPattern.MatchString(meter) || !dayPattern.MatchString(start) || !dayPattern.MatchString(end) {
			http.Error(w, "usage_point_id, start and end are required", http.StatusBadRequest)
			return
		}
		given := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !hmac.Equal([]byte(given), []byte(e.accessKey(meter))) {
			http.Error(w, "not linked", http.StatusUnauthorized)
			return
		}
		upstream := url.Values{"usage_point_id": {meter}, "start": {start}, "end": {end}}
		status, body, err := e.get(r.Context(), path+"?"+upstream.Encode())
		if err != nil {
			http.Error(w, "Enedis unreachable", http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.WriteHeader(status)
		_, _ = w.Write(body)
	}
}

// get calls the data API with the operator token, renewing it once if Enedis no longer accepts it.
func (e *enedis) get(ctx context.Context, pathAndQuery string) (int, []byte, error) {
	for attempt := 0; attempt < 2; attempt++ {
		token, err := e.accessToken(ctx, attempt > 0)
		if err != nil {
			return 0, nil, err
		}
		request, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimSuffix(e.config.enedisAPIURL, "/")+pathAndQuery, nil)
		if err != nil {
			return 0, nil, err
		}
		request.Header.Set("Authorization", "Bearer "+token)
		request.Header.Set("Accept", "application/json")
		response, err := e.client.Do(request)
		if err != nil {
			return 0, nil, err
		}
		body, err := io.ReadAll(io.LimitReader(response.Body, maxBody))
		response.Body.Close()
		if err != nil {
			return 0, nil, err
		}
		if response.StatusCode == http.StatusUnauthorized && attempt == 0 {
			continue
		}
		return response.StatusCode, body, nil
	}
	return http.StatusUnauthorized, nil, nil
}

// accessToken is Maison's own token (client credentials), kept in memory until shortly before it expires.
func (e *enedis) accessToken(ctx context.Context, renew bool) (string, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !renew && e.token != "" && time.Now().Before(e.tokenExpiry) {
		return e.token, nil
	}
	form := url.Values{
		"grant_type":    {"client_credentials"},
		"client_id":     {e.config.enedisClientID},
		"client_secret": {e.config.enedisClientSecret},
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimSuffix(e.config.enedisAPIURL, "/")+"/oauth2/v3/token", strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := e.client.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf("token refused: %d", response.StatusCode)
	}
	var token struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&token); err != nil {
		return "", err
	}
	if token.AccessToken == "" {
		return "", errors.New("token missing")
	}
	e.token = token.AccessToken
	e.tokenExpiry = time.Now().Add(time.Duration(max(token.ExpiresIn-60, 0)) * time.Second)
	return e.token, nil
}
