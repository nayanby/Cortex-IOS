# Connect iOS to the existing CORTEX backend

The existing Android configuration identifies project `cortex-v1b` and Storage bucket `cortex-v1b.firebasestorage.app`. The iOS target's bundle ID is `com.cortex.notes`. Reuse the existing project so the consumer catalog and accounts refer to the same backend.

Console inspection on 27 October 2026 confirmed there are two Android registrations and one web registration, with no Apple app. The Apple form is prepared with bundle ID `com.cortex.notes` and nickname `Cortex Consumer iOS`; registration awaits action-time confirmation before submitting.

## Configuration needed

1. Open [CORTEX Firebase project settings](https://console.firebase.google.com/project/cortex-v1b/settings/general).
2. Under **Your apps**, select an existing Apple app with bundle ID `com.cortex.notes`, or choose **Add app → iOS+** and register that bundle ID. An App Store ID is not needed at this stage.
3. Download its `GoogleService-Info.plist`.
4. Keep it locally for integration. It is currently ignored by Git. Do not upload a service-account private key, Android signing key, account password, or Apple signing credential in its place.

Registration alone does not connect the current build. The Firebase Apple SDK, initialization, Google sign-in URL handling, App Check and account/device policy still need implementation. The current app makes no Firebase requests.

## Integration checks

- Verify the plist's bundle ID and project ID before enabling the SDK.
- Configure the same Email/Password and Google auth providers as Android.
- Implement profile and entitlement checks separately from Firebase Authentication; Firebase sign-in must not grant access on its own.
- Register the Apple App Check provider and use debug tokens only in authorized development builds. Do not relax production backend rules to make simulator requests pass.
- Preserve existing note, snapshot, flashcard and quiz paths and serialized schemas.
- Use a dedicated test account to check trial start, registration limits, concurrent sessions, revoked access, offline behavior and cross-platform data round trips.

Official references: [Firebase Apple setup](https://firebase.google.com/docs/ios/setup), [download Apple app configuration](https://support.google.com/firebase/answer/7015592).
