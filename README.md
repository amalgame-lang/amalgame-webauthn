# amalgame-webauthn

A **WebAuthn / passkeys** relying-party (server) verifier for Amalgame.
It checks the two ceremonies a server is responsible for — registration
(attestation) and authentication (assertion) — for **ES256 (P-256)**
credentials, the algorithm platform authenticators and passkeys use.

The cryptography lives in [`amalgame-crypto`](https://github.com/amalgame-lang/amalgame-crypto)
(`JwsKey.FromCoseEc2` + `VerifyDer`); this package adds the WebAuthn
ceremony logic + a small decode-only CBOR reader.

## Install

```sh
amc package add crypto
amc package add webauthn
```

## Use

```amalgame
import Amalgame.Crypto
import Amalgame.WebAuthn

let rp = new WebAuthn("example.com", "https://example.com")   // rpId, origin

// 1. Begin registration / login: mint a challenge, store it in the session.
let challenge = rp.NewChallenge()           // 32-byte CSPRNG, base64url

// 2a. Registration — the browser posts clientDataJSON + attestationObject
//     (base64url; decode with Bytes.FromBase64Url before calling).
let reg = rp.VerifyRegistration(clientDataJson, attestationObject, challenge)
if (reg.Ok) {
    // Persist these against the user account:
    //   reg.CredentialId (base64url), reg.CoseX, reg.CoseY, reg.SignCount
}

// 2b. Authentication — the browser posts clientDataJSON + authenticatorData
//     + signature, plus the credentialId (to look up the stored key).
let cred = new StoredCredential(credentialId, coseX, coseY, lastSignCount)
let asr = rp.VerifyAssertion(clientDataJson, authenticatorData, signature, cred, challenge)
if (asr.Ok) {
    // Login OK. Persist the advanced counter:
    //   cred.SignCount = asr.SignCount
}
```

## What it checks

**Registration** (`VerifyRegistration`):
- clientDataJSON `type == "webauthn.create"`, `challenge` matches, `origin` matches;
- the attestationObject CBOR, the `authData` rpIdHash equals `SHA-256(rpId)`;
- the **User-Present** flag and attested-credential-data flag are set;
- extracts + validates the COSE EC2 / ES256 / P-256 public key and the credential id.

**Authentication** (`VerifyAssertion`):
- clientDataJSON `type == "webauthn.get"`, `challenge` + `origin` match;
- `authenticatorData` rpIdHash equals `SHA-256(rpId)`, User-Present set;
- **verifies the assertion signature** over `authenticatorData ‖ SHA-256(clientDataJSON)`
  with the stored public key — the cryptographic core of the login;
- enforces a **strictly-increasing signature counter** (cloned-authenticator detection).

Verification never throws — every failure returns a result with `Ok = false`
and a specific `Error`.

## Scope (v0.1.0)

- **ES256 (P-256)** credentials — what passkeys / platform authenticators use.
- Attestation format **`none`** — the common, privacy-preserving default.
  The public key is bound by the **assertion signature at login**, not by an
  attestation certificate chain, so registration with `none` is the
  recommended posture for most relying parties.
- Attestation-statement / certificate-chain verification (`packed`, `tpm`,
  `android-key`, `fido-u2f`) is a **future** addition — those formats are
  accepted for key *extraction* but no attestation trust is asserted. If you
  require hardware attestation, do not rely on this yet.

## License

Apache-2.0.
