package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
)

const meter = "12345678901234"

// fakeEnedis answers the token and data routes like Enedis's API, and counts what it is asked.
type fakeEnedis struct {
	tokens       atomic.Int32
	dataCalls    atomic.Int32
	rejectFirst  atomic.Bool
	loadCurve    int
	lastAuth     atomic.Value
	lastDataPath atomic.Value
}

func (f *fakeEnedis) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/oauth2/v3/token":
		_ = r.ParseForm()
		if r.PostForm.Get("grant_type") != "client_credentials" || r.PostForm.Get("client_secret") != "secret" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		n := f.tokens.Add(1)
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"access_token": "token-`+string(rune('0'+n))+`", "expires_in": 12600, "token_type": "Bearer"}`)
	default:
		f.dataCalls.Add(1)
		f.lastAuth.Store(r.Header.Get("Authorization"))
		f.lastDataPath.Store(r.URL.Path + "?" + r.URL.RawQuery)
		if f.rejectFirst.CompareAndSwap(true, false) {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		if f.loadCurve != 0 && strings.Contains(r.URL.Path, "consumption_load_curve") {
			w.WriteHeader(f.loadCurve)
			_, _ = io.WriteString(w, `{"error": "ADAM-ERR0123"}`)
			return
		}
		_, _ = io.WriteString(w, `{"meter_reading": {"usage_point_id": "`+meter+`", "interval_reading": [{"value": "540", "date": "2026-10-21 00:30:00"}]}}`)
	}
}

func setUp(t *testing.T) (*fakeEnedis, http.Handler, Config) {
	t.Helper()
	fake := &fakeEnedis{}
	upstream := httptest.NewTLSServer(fake)
	t.Cleanup(upstream.Close)
	config, err := loadConfig(func(key string) string {
		return map[string]string{
			"RELAY_SIGNING_KEY":    strings.Repeat("k", 48),
			"ENEDIS_CLIENT_ID":     "maison",
			"ENEDIS_CLIENT_SECRET": "secret",
			"ENEDIS_API_URL":       upstream.URL,
		}[key]
	})
	if err != nil {
		t.Fatal(err)
	}
	return fake, newRouter(config, upstream.Client()), config
}

func serve(handler http.Handler, method, target string, header http.Header) *httptest.ResponseRecorder {
	request := httptest.NewRequest(method, target, nil)
	for key, values := range header {
		request.Header[key] = values
	}
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	return recorder
}

func TestConfigurationRefusesMissingSecrets(t *testing.T) {
	_, err := loadConfig(func(string) string { return "" })
	if err == nil || !strings.Contains(err.Error(), "RELAY_SIGNING_KEY") || !strings.Contains(err.Error(), "ENEDIS_CLIENT_ID") {
		t.Fatalf("expected both problems, got %v", err)
	}
	_, err = loadConfig(func(key string) string {
		return map[string]string{
			"RELAY_SIGNING_KEY": strings.Repeat("k", 48), "ENEDIS_CLIENT_ID": "id", "ENEDIS_CLIENT_SECRET": "s",
			"ENEDIS_API_URL": "http://insecure.example",
		}[key]
	})
	if err == nil || !strings.Contains(err.Error(), "https") {
		t.Fatalf("expected an https error, got %v", err)
	}
}

func TestAuthorizeSendsThePersonToEnedisWithTheStateUnchanged(t *testing.T) {
	_, handler, _ := setUp(t)
	response := serve(handler, http.MethodGet, "/enedis/authorize?state=abc-123_XYZ", nil)
	if response.Code != http.StatusFound {
		t.Fatalf("status %d", response.Code)
	}
	location, _ := url.Parse(response.Header().Get("Location"))
	if location.Host != "mon-compte-particulier.enedis.fr" || location.Path != "/dataconnect/v1/oauth2/authorize" {
		t.Fatalf("unexpected target %s", location)
	}
	query := location.Query()
	if query.Get("client_id") != "maison" || query.Get("state") != "abc-123_XYZ" || query.Get("duration") != "P1Y" || query.Get("response_type") != "code" {
		t.Fatalf("unexpected query %v", query)
	}
	if strings.Contains(location.String(), "secret") {
		t.Fatal("the client secret leaked into the redirect")
	}
}

func TestAuthorizeRefusesAStateThatCouldInjectIntoTheRedirect(t *testing.T) {
	_, handler, _ := setUp(t)
	for _, state := range []string{"", "short", "abc&client_id=evil1234", strings.Repeat("a", 129)} {
		if response := serve(handler, http.MethodGet, "/enedis/authorize?state="+url.QueryEscape(state), nil); response.Code != http.StatusBadRequest {
			t.Fatalf("state %q: status %d", state, response.Code)
		}
	}
}

func TestCallbackHandsTheAppTheMeterAndItsKey(t *testing.T) {
	_, handler, _ := setUp(t)
	response := serve(handler, http.MethodGet, "/enedis/callback?code=ignored&state=abc-12345&usage_point_id="+meter, nil)
	location, _ := url.Parse(response.Header().Get("Location"))
	if location.Scheme != "maison" || location.Host != "grid" || location.Path != "/enedis" {
		t.Fatalf("unexpected callback %s", location)
	}
	query := location.Query()
	if query.Get("usage_point_id") != meter || query.Get("state") != "abc-12345" || len(query.Get("access")) < 40 {
		t.Fatalf("unexpected query %v", query)
	}
	if query.Has("code") {
		t.Fatal("the authorization code must not reach the app")
	}
}

func TestCallbackPassesARefusalOn(t *testing.T) {
	_, handler, _ := setUp(t)
	response := serve(handler, http.MethodGet, "/enedis/callback?state=abc-12345&error=access_denied", nil)
	query, _ := url.ParseQuery(strings.SplitN(response.Header().Get("Location"), "?", 2)[1])
	if query.Get("error") != "access_denied" || query.Has("access") {
		t.Fatalf("unexpected query %v", query)
	}
	response = serve(handler, http.MethodGet, "/enedis/callback?state=abc-12345&usage_point_id=12", nil)
	query, _ = url.ParseQuery(strings.SplitN(response.Header().Get("Location"), "?", 2)[1])
	if query.Get("error") != "invalid_usage_point" {
		t.Fatalf("unexpected query %v", query)
	}
}

func TestReadingsNeedTheKeyOfThatMeter(t *testing.T) {
	fake, handler, config := setUp(t)
	e := newEnedis(config, nil)
	path := "/enedis/daily_consumption?usage_point_id=" + meter + "&start=2026-10-20&end=2026-10-21"

	if response := serve(handler, http.MethodGet, path, nil); response.Code != http.StatusUnauthorized {
		t.Fatalf("without a key: %d", response.Code)
	}
	otherMeter := e.accessKey("99999999999999")
	if response := serve(handler, http.MethodGet, path, http.Header{"Authorization": {"Bearer " + otherMeter}}); response.Code != http.StatusUnauthorized {
		t.Fatalf("with another meter's key: %d", response.Code)
	}
	if fake.dataCalls.Load() != 0 {
		t.Fatal("Enedis was asked without a valid key")
	}

	response := serve(handler, http.MethodGet, path, http.Header{"Authorization": {"Bearer " + e.accessKey(meter)}})
	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), `"interval_reading"`) {
		t.Fatalf("with the key: %d %s", response.Code, response.Body.String())
	}
	if response.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("readings must not be cached")
	}
	if got := fake.lastDataPath.Load().(string); got != "/metering_data_dc/v5/daily_consumption?end=2026-10-21&start=2026-10-20&usage_point_id="+meter {
		t.Fatalf("unexpected upstream request %s", got)
	}
	if fake.lastAuth.Load().(string) != "Bearer token-1" {
		t.Fatal("the operator token was not sent")
	}
}

func TestMalformedRequestsNeverReachEnedis(t *testing.T) {
	fake, handler, config := setUp(t)
	key := newEnedis(config, nil).accessKey(meter)
	for _, query := range []string{
		"usage_point_id=" + meter + "&start=2026-10-20",
		"usage_point_id=" + meter + "&start=yesterday&end=2026-10-21",
		"usage_point_id=12&start=2026-10-20&end=2026-10-21",
	} {
		response := serve(handler, http.MethodGet, "/enedis/consumption_load_curve?"+query, http.Header{"Authorization": {"Bearer " + key}})
		if response.Code != http.StatusBadRequest {
			t.Fatalf("%s: %d", query, response.Code)
		}
	}
	if fake.dataCalls.Load() != 0 {
		t.Fatal("Enedis was asked a malformed request")
	}
}

func TestAMissingLoadCurveKeepsEnedisStatusForTheApp(t *testing.T) {
	fake, handler, config := setUp(t)
	fake.loadCurve = http.StatusNotFound
	key := newEnedis(config, nil).accessKey(meter)
	response := serve(handler, http.MethodGet, "/enedis/consumption_load_curve?usage_point_id="+meter+"&start=2026-10-20&end=2026-10-21",
		http.Header{"Authorization": {"Bearer " + key}})
	if response.Code != http.StatusNotFound || !strings.Contains(response.Body.String(), "ADAM-ERR0123") {
		t.Fatalf("%d %s", response.Code, response.Body.String())
	}
}

func TestTheOperatorTokenIsReusedThenRenewedWhenRefused(t *testing.T) {
	fake, handler, config := setUp(t)
	key := newEnedis(config, nil).accessKey(meter)
	path := "/enedis/daily_consumption?usage_point_id=" + meter + "&start=2026-10-20&end=2026-10-21"
	header := http.Header{"Authorization": {"Bearer " + key}}

	serve(handler, http.MethodGet, path, header)
	serve(handler, http.MethodGet, path, header)
	if fake.tokens.Load() != 1 {
		t.Fatalf("expected one token, got %d", fake.tokens.Load())
	}

	fake.rejectFirst.Store(true)
	response := serve(handler, http.MethodGet, path, header)
	if response.Code != http.StatusOK || fake.tokens.Load() != 2 {
		t.Fatalf("expected a renewed token and success, got %d with %d tokens", response.Code, fake.tokens.Load())
	}
}

func TestHealth(t *testing.T) {
	_, handler, _ := setUp(t)
	if response := serve(handler, http.MethodGet, "/healthz", nil); response.Code != http.StatusNoContent {
		t.Fatalf("status %d", response.Code)
	}
}
