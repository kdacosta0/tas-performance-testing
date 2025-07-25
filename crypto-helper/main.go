package main

import (
	"bytes"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	mrand "math/rand"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/sigstore/sigstore/pkg/signature"
	"github.com/sigstore/sigstore/pkg/signature/options"
)

// TsaRequest defines the structure for a request to the Timestamp Authority
type TsaRequest struct {
	ArtifactHash  string `json:"artifactHash"`
	Certificates  bool   `json:"certificates"`
	HashAlgorithm string `json:"hashAlgorithm"`
	Nonce         int64  `json:"nonce"`
}

var (
	artifactHash []byte
)

// CryptoComponents defines the structure for the cryptographic materials
// generated by the helper service
type CryptoComponents struct {
	PublicKeyBase64    string `json:"publicKeyBase64"`
	SignedEmailAddress string `json:"signedEmailAddress"`
	ArtifactHash       string `json:"artifactHash"`
	ArtifactSignature  string `json:"artifactSignature"`
}

func init() {
	log.Println("[INFO] Generating a single, random artifact hash for the service...")

	randomHash := make([]byte, 32)
	if _, err := rand.Read(randomHash); err != nil {
		log.Fatalf("[FATAL] Could not generate the global artifact hash: %v", err)
	}

	artifactHash = randomHash
	log.Printf("[INFO] Global artifact hash generated and cached: %s", hex.EncodeToString(artifactHash))
}

// generatorHandler creates necessary cryptographic components for a signing operation
func generatorHandler(w http.ResponseWriter, r *http.Request) {
	signer, privateKey, err := signature.NewECDSASignerVerifier(elliptic.P256(), rand.Reader, crypto.SHA256)
	if err != nil {
		http.Error(w, fmt.Sprintf("[ERROR] Error creating ECDSA signer: %v", err), http.StatusInternalServerError)
		return
	}

	pubKeyBytes, err := x509.MarshalPKIXPublicKey(privateKey.Public())
	if err != nil {
		http.Error(w, fmt.Sprintf("[ERROR] Error marshalling public key: %v", err), http.StatusInternalServerError)
		return
	}
	publicKeyBase64 := base64.StdEncoding.EncodeToString(pubKeyBytes)

	emailToSign := "jdoe@redhat.com"
	proofOfPossession, err := signer.SignMessage(strings.NewReader(emailToSign), options.WithContext(r.Context()))
	if err != nil {
		http.Error(w, "[ERROR] Error signing email address", http.StatusInternalServerError)
		return
	}

	log.Printf("[INFO] Using the global artifact hash: %s", hex.EncodeToString(artifactHash))

	artifactSignature, err := ecdsa.SignASN1(rand.Reader, privateKey, artifactHash)
	if err != nil {
		http.Error(w, fmt.Sprintf("[ERROR] Error signing artifact hash: %v", err), http.StatusInternalServerError)
		return
	}

	response := CryptoComponents{
		PublicKeyBase64:    publicKeyBase64,
		SignedEmailAddress: base64.StdEncoding.EncodeToString(proofOfPossession),
		ArtifactHash:       hex.EncodeToString(artifactHash),
		ArtifactSignature:  base64.StdEncoding.EncodeToString(artifactSignature),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// timestampHandler forwards a request to a Timestamp Authority (TSA)
// It takes a signature, hashes it, and sends it to the TSA specified by the TSA_URL env var
func timestampHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "[ERROR] Method not allowed, must be POST", http.StatusMethodNotAllowed)
		return
	}

	signatureToTimestamp, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, fmt.Sprintf("[ERROR] Error reading request body: %v", err), http.StatusInternalServerError)
		return
	}

	tsaURL := os.Getenv("TSA_URL")
	if tsaURL == "" {
		log.Fatalf("[FATAL] TSA_URL environment variable not set")
	}

	// Create a new local random generator to avoid using the deprecated global Seed
	source := mrand.NewSource(time.Now().UnixNano())
	localRand := mrand.New(source)

	signatureHashBytes := sha256.Sum256(signatureToTimestamp)
	tsaRequestPayload := TsaRequest{
		ArtifactHash:  base64.StdEncoding.EncodeToString(signatureHashBytes[:]),
		Certificates:  true,
		HashAlgorithm: "sha256",
		Nonce:         localRand.Int63(),
	}
	tsaRequestBytes, err := json.Marshal(tsaRequestPayload)
	if err != nil {
		http.Error(w, fmt.Sprintf("[ERROR] Error marshalling TSA request: %v", err), http.StatusInternalServerError)
		return
	}

	tsaResp, err := http.Post(tsaURL, "application/json", bytes.NewBuffer(tsaRequestBytes))
	if err != nil {
		http.Error(w, fmt.Sprintf("[ERROR] TSA request failed (network error): %v", err), http.StatusInternalServerError)
		return
	}
	defer tsaResp.Body.Close()

	if tsaResp.StatusCode != http.StatusOK && tsaResp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(tsaResp.Body)
		http.Error(w, fmt.Sprintf("[ERROR] TSA server returned non-OK status: %d, Body: %s", tsaResp.StatusCode, string(body)), http.StatusBadGateway)
		return
	}

	tsaTimestampBytes, err := io.ReadAll(tsaResp.Body)
	if err != nil {
		http.Error(w, fmt.Sprintf("[ERROR] Error reading TSA response body: %v", err), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/timestamp-reply")
	w.Write(tsaTimestampBytes)
}

func main() {
	http.HandleFunc("/generate-payloads", generatorHandler)
	http.HandleFunc("/get-timestamp", timestampHandler)

	log.Println("[INFO] Go crypto helper service listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
