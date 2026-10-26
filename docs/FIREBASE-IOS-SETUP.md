# Connect iOS to the existing CORTEX backend

The existing Android configuration identifies project `cortex-v1b` and Storage bucket `cortex-v1b.firebasestorage.app`. The iOS target's bundle ID is `com.cortex.notes`. Reuse the existing project so the consumer catalog and accounts refer to the same backend.

On 27 October 2026, after explicit user approval, `Cortex Consumer iOS` was registered with bundle ID `com.cortex.notes`. The Firebase CLI independently verified its active Apple app ID: `1:302875225635:ios:feae2129a9dc52c49c0b96`. Its actual configuration was retrieved to the Git-ignored `Config/GoogleService-Info.plist` using the existing local Firebase CLI login.

## Configuration needed

1. Open [CORTEX Firebase project settings](https://console.firebase.google.com/project/cortex-v1b/settings/general).
2. Under **Your apps**, select an existing Apple app with bundle ID `com.cortex.notes`, or choose **Add app → iOS+** and register that bundle ID. An App Store ID is not needed at this stage.
3. Download its `GoogleService-Info.plist`.
4. Keep it locally for integration. It is currently ignored by Git. Do not upload a service-account private key, Android signing key, account password, or Apple signing credential in its place.

FirebaseCore 12.19.3 and application-delegate initialization are implemented. The app validates the project ID, bundle ID, sender ID, Apple app ID and presence of the client API key before configuring the SDK. This does not establish an authenticated connection or grant consumer access. Google sign-in, App Check, account/device policy and catalog downloads still need implementation. No production backend rules or user data were changed.

The configuration remains local. The unsigned GitHub build can compile and test the offline app without it. A cloud-built app will need the configuration supplied to its build environment before Firebase initialization can run there.

Verification: [cloud build 40411806905](https://github.com/nayanby/Cortex-IOS/actions/runs/40411806905) passed compilation and simulator tests for commit `b3c6f9f`. The cloud run did not receive the live configuration; authenticated backend access has not been tested.

## Integration checks

- Verify the plist's bundle ID and project ID before enabling the SDK.
- Configure the same Email/Password and Google auth providers as Android.
- Implement profile and entitlement checks separately from Firebase Authentication; Firebase sign-in must not grant access on its own.
- Register the Apple App Check provider and use debug tokens only in authorized development builds. Do not relax production backend rules to make simulator requests pass.
- Preserve existing note, snapshot, flashcard and quiz paths and serialized schemas.
- Use a dedicated test account to check trial start, registration limits, concurrent sessions, revoked access, offline behavior and cross-platform data round trips.

Official references: [Firebase Apple setup](https://firebase.google.com/docs/ios/setup), [download Apple app configuration](https://support.google.com/firebase/answer/7015592).
