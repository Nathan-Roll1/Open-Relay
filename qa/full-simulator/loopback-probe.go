// This test proxy exposes only the disposable Open WebUI service on loopback.
// Log route names for the sign-in journey. Never log payloads, queries or credentials.
package main

import (
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
)

func main() {
	target, err := url.Parse("http://127.0.0.1:8319")
	if err != nil {
		log.Fatal(err)
	}
	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.ModifyResponse = func(response *http.Response) error {
		switch path := response.Request.URL.Path; path {
		case "/health", "/api/config", "/api/v1/auths", "/api/v1/auths/", "/api/v1/auths/signin":
			origin := "app"
			if response.Request.Header.Get("X-Fourier-Diagnostic") == "simulator" {
				origin = "simulator-control"
			}
			fmt.Printf("%s %s %s %d\n", origin, response.Request.Method, path, response.StatusCode)
		}
		return nil
	}
	log.Fatal(http.ListenAndServe("127.0.0.1:8320", proxy))
}
