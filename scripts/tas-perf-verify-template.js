import http from 'k6/http';
import { check, group } from 'k6';
import { SharedArray } from 'k6/data';
import { b64decode } from 'k6/encoding';

// Simulates a verification workflow using a list of pre-existing Rekor UUIDs.
const uuidFile = __ENV.REKOR_UUID_FILE || '../rekor_uuids_smoke.txt';
export const options = {};

// Load Rekor UUIDs to be shared across all VUs.
const uuids = new SharedArray('rekor-uuids', function () {
    try {
        return open(uuidFile).split('\n').filter(s => s.trim() !== '');
    } catch (e) {
        return [''];
    }
});


export default function () {
    // Abort if the UUID file is missing or empty.
    if (uuids.length === 0 || uuids[0] === '') {
        console.error(`Error: UUID file '${uuidFile}' is empty or not found. Run a signing test first`);
        return;
    }
    
    const randomIndex = Math.floor(Math.random() * uuids.length);
    const uuidToVerify = uuids[randomIndex];

    const REKOR_URL = __ENV.REKOR_URL;
    const TSA_URL = __ENV.TSA_URL;

    group('Workflow: Verify Signature', function() {
        group('1. Rekor: Get Log Entry by UUID', function () {
            const getEntryUrl = `${REKOR_URL}/api/v1/log/entries/${uuidToVerify}`;
            const res = http.get(getEntryUrl);

            const statusOK = check(res, { 'Rekor GET returned HTTP 200': (r) => r.status === 200 });

            if (statusOK) {
                const rekorEntry = res.json();
                check(rekorEntry, {
                    'Rekor response contains the correct entry UUID': (entry) => entry.hasOwnProperty(uuidToVerify),
                });

                try {
                    const entryData = rekorEntry[uuidToVerify];
                    const decodedBody = JSON.parse(b64decode(entryData.body, 'std', 's'));
                    check(decodedBody, {
                        'Rekor entry body contains a signature block': (b) => b.spec && b.spec.signature,
                    });
                } catch (e) {
                    check(null, { 'Rekor response body was not valid JSON': () => false });
                }
            }
        });

        // Get the TSA's certificate chain to verify the timestamp.
        group('2. TSA: Get Certificate Chain', function() {
            const certChainUrl = `${TSA_URL}/certchain`;
            const res = http.get(certChainUrl);
            check(res, { 'TSA GET certchain returned HTTP 200': (r) => r.status === 200 });
        });
    });
}
