package main

// Config comes from the environment only, so secrets never sit in the image or the repository.
type Config struct {
	port string
}

func loadConfig(env func(string) string) (Config, error) {
	return Config{port: value(env, "PORT", "8080")}, nil
}

func value(env func(string) string, key, fallback string) string {
	if found := env(key); found != "" {
		return found
	}
	return fallback
}
