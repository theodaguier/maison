package main

import (
	"errors"
	"fmt"
	"net/url"
)

// Config comes from the environment only, so secrets never sit in the image or the repository.
type Config struct {
	port string
	// signingKey signs the access key the app receives for one meter. Changing it unlinks every home.
	signingKey []byte
	// appCallback is where the consent comes back to the app.
	appCallback string

	enedisClientID     string
	enedisClientSecret string
	// enedisAuthorizeURL is Enedis's consent page; enedisAPIURL its data API (production or sandbox).
	enedisAuthorizeURL string
	enedisAPIURL       string
	// enedisDuration is how long the consent lasts, in ISO 8601 ("P1Y").
	enedisDuration string
}

func loadConfig(env func(string) string) (Config, error) {
	config := Config{
		port:               value(env, "PORT", "8080"),
		signingKey:         []byte(env("RELAY_SIGNING_KEY")),
		appCallback:        value(env, "APP_CALLBACK", "maison://grid"),
		enedisClientID:     env("ENEDIS_CLIENT_ID"),
		enedisClientSecret: env("ENEDIS_CLIENT_SECRET"),
		enedisAuthorizeURL: value(env, "ENEDIS_AUTHORIZE_URL", "https://mon-compte-particulier.enedis.fr/dataconnect/v1/oauth2/authorize"),
		enedisAPIURL:       value(env, "ENEDIS_API_URL", "https://ext.prod.api.enedis.fr"),
		enedisDuration:     value(env, "ENEDIS_CONSENT_DURATION", "P1Y"),
	}
	var problems []error
	if len(config.signingKey) < 32 {
		problems = append(problems, errors.New("RELAY_SIGNING_KEY must be at least 32 characters (openssl rand -base64 48)"))
	}
	if config.enedisClientID == "" || config.enedisClientSecret == "" {
		problems = append(problems, errors.New("ENEDIS_CLIENT_ID and ENEDIS_CLIENT_SECRET are required"))
	}
	for _, address := range []string{config.enedisAuthorizeURL, config.enedisAPIURL} {
		if parsed, err := url.Parse(address); err != nil || parsed.Scheme != "https" {
			problems = append(problems, fmt.Errorf("%q must be an https address", address))
		}
	}
	return config, errors.Join(problems...)
}

func value(env func(string) string, key, fallback string) string {
	if found := env(key); found != "" {
		return found
	}
	return fallback
}
