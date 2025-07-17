import http from 'k6/http';
import { check, group, fail } from 'k6';
import { b64encode } from 'k6/encoding';

let createdUUIDs = [];

export function setup() {
    console.log("Fetching a single OIDC token for the entire test run...");
    const issuerURL = __ENV.OIDC_ISSUER_URL;
    const user = __ENV.OIDC_USER;
    const password = __ENV.OIDC_PASSWORD;
    const clientID = __ENV.OIDC_CLIENT_ID;
    if (!issuerURL || !user || !password || !clientID) {
        fail("Missing OIDC environment variables.");
        return null;
    }
    const tokenURL = `${issuerURL}/protocol/openid-connect/token`;
    const payload = {
        username: user,
        password: password,
        scope: "openid",
        client_id: clientID,
        grant_type: "password",
    };
    const res = http.post(tokenURL, payload);
    if (res.status !== 200) {
        fail(`OIDC token request failed: ${res.status} ${res.body}`);
    }
    console.log("OIDC Token successfully retrieved. Starting VU iterations.");
    return { token: res.json("access_token") };
}

export const options = {
    scenarios: {
        signing_workload: {
            executor: 'constant-vus',
            exec: 'signWorkflow',
            vus: __ENV.SIGN_VUS || 10,
            duration: __ENV.TEST_DURATION || '10m',
        },
        verification_workload: {
            executor: 'constant-vus',
            exec: 'verifyWorkflow',
            vus: __ENV.VERIFY_VUS || 40,
            duration: __ENV.TEST_DURATION || '10m',
        },
    },
};

export function signWorkflow(data) {
    const authToken = data.token;
    const FULCIO_URL = __ENV.FULCIO_URL + "/api/v1/signingCert";
    const REKOR_URL = __ENV.REKOR_URL + "/api/v1/log/entries";

    const helperRes = http.get('http://localhost:8080/generate-payloads', { tags: { name: "Helper_GetCrypto" } });
    if (helperRes.status !== 200) fail(`Failed to get crypto components from helper: ${helperRes.status} ${helperRes.body}`);
    
    const crypto = helperRes.json();
    const liveHeaders = { Authorization: `Bearer ${authToken}`, "Content-Type": "application/json" };
    let fulcioCertificatePEM;
    let newRekorUUID = null;

    group("Sign:Workflow", function () {
        group("Sign:1. Fulcio: Request Certificate", function () {
            const fulcioPayload = JSON.stringify({
                publicKey: { content: crypto.publicKeyBase64 },
                signedEmailAddress: crypto.signedEmailAddress,
            });
            const res = http.post(FULCIO_URL, fulcioPayload, { headers: liveHeaders, tags: { name: "Fulcio_RequestCert" } });
            if (check(res, { "Fulcio returned HTTP 201": (r) => r.status === 201 })) {
                const certRegex = /(-----BEGIN CERTIFICATE-----[^]+?-----END CERTIFICATE-----)/;
                const match = res.body.match(certRegex);
                if (match && match[0]) fulcioCertificatePEM = match[0];
            }
        });

        if (!fulcioCertificatePEM) fail("Failed to get certificate from Fulcio, cannot proceed");

        group("Sign:2. Rekor: Create HashedRekord Entry", function () {
            const rekorPayload = JSON.stringify({
                apiVersion: "0.0.1",
                kind: "hashedrekord",
                spec: {
                    signature: { content: crypto.artifactSignature, publicKey: { content: b64encode(fulcioCertificatePEM) } },
                    data: { hash: { algorithm: "sha256", value: crypto.artifactHash } },
                },
            });
            const res = http.post(REKOR_URL, rekorPayload, { headers: { "Content-Type": "application/json" }, tags: { name: "Rekor_CreateHashedRekord" } });
            if (check(res, { "Rekor (hashedrekord) returned HTTP 201": (r) => r.status === 201 })) {
                const location = res.headers["Location"];
                if (location) {
                    newRekorUUID = location.split("/").pop();
                    createdUUIDs.push(newRekorUUID);
                }
            }
        });
    });
}

export function verifyWorkflow() {
    if (createdUUIDs.length === 0) {
        return;
    }
    
    const randomIndex = Math.floor(Math.random() * createdUUIDs.length);
    const uuidToVerify = createdUUIDs[randomIndex];

    if (!uuidToVerify) return; 

    const REKOR_URL = __ENV.REKOR_URL;

    group('Verify:Workflow', function() {
        group('Verify:1. Rekor: Get Log Entry by UUID', function () {
            const getEntryUrl = `${REKOR_URL}/api/v1/log/entries/${uuidToVerify}`;
            const res = http.get(getEntryUrl, { tags: { name: 'Rekor_GetEntryByUUID' } });
            check(res, { 'Rekor GET returned HTTP 200': (r) => r.status === 200 });
        });
    });
}