/*
 * facade-stub.h — empty runtime header for the WebAuthn facade.
 *
 * The package's API is implemented in `facade.am` (pure Amalgame);
 * this file exists only because the manifest's `[stdlib].header`
 * field is required by PackageRegistry.LoadFrom in amc. The user
 * binary's #include of this header is a no-op.
 */
