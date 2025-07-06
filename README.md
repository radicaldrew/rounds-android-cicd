# Rounds Android CI/CD Pipeline on Google Cloud Platform

Rounds CI/CD Terraform configuration sets up a complete Android CI/CD pipeline on Google Cloud Platform. The pipeline provides Rounds with automated Android app builds with comprehensive monitoring, cost optimization, and security features.

## Features

### Core Pipeline Features
- **Automated Builds**: Triggered by file uploads to Cloud Storage
- **Android Builder**: Custom Docker image with Android SDK and Gradle
- **Caching**: Aggressive caching at multiple levels for faster builds
- **Artifact Management**: Automatic storage and retention of build outputs
- **Signing Support**: Secure APK signing with Secret Manager integration
- **Webhook Notifications**: Real-time build status notifications

### Monitoring & Observability
- **Custom Dashboards**: Cloud Monitoring dashboard with build metrics
- **Alerting**: Automated alerts for build failures and performance issues
- **Log Analysis**: Structured logging with log-based metrics
- **SLOs**: Service Level Objectives for build success rate
- **Cost Monitoring**: Budget alerts and cost optimization tracking

### Security & Compliance
- **IAM**: Principle of least privilege with dedicated service accounts
- **Secret Management**: Keystore and credentials stored in Secret Manager
- **Network Security**: Isolated build environments
- **Audit Logging**: Complete audit trail for all pipeline activities

### Cost Optimization
- **Worker Pools**: Cost-optimized build instances
- **Lifecycle Policies**: Automatic cleanup of old artifacts
- **Caching Strategy**: Reduced build times and resource usage
- **Budget Controls**: Automated cost monitoring and alerts

## Prerequisites

- Google Cloud Platform account with billing enabled
- Terraform >= 1.0 installed
- `gcloud` CLI installed and authenticated
- Android project source code
- (Optional) Android keystore for signed builds

## Quick Start

### 1. Clone and Configure

```bash
git clone <this-repo>
cd android-cicd-terraform
cp terraform.tfvars.example terraform.tfvars
```

### 2. Update Configuration

Edit `terraform.tfvars` with your specific values:

```hcl
project_id = "rounds-android-cicd"
region     = "us-central1"
webhook_url = "https://project.webhook.rounds.com"
notification_email = "your-email@rounds.com"
```

### 3. Initialize and Apply

```bash
terraform init
terraform plan
terraform apply
```

### 4. Upload Android Project

```bash
# Zip your Android project
zip -r android-app.zip /path/to/your/android/project

# Upload to trigger build
gsutil cp android-app.zip gs://YOUR_PROJECT_ID-source-uploads/
```

## Detailed Setup

### Android Project Requirements

Your Android project should have the following structure:

```
your-android-project/
├── app/
│   ├── build.gradle
│   └── src/
├── gradle/
├── build.gradle
├── settings.gradle
└── gradlew
```

### Required Gradle Configuration

Ensure your `app/build.gradle` includes:

```gradle
android {
    compileSdk 34
    
    defaultConfig {
        minSdk 21
        targetSdk 34
        // ... other config
    }
    
    // For signed builds
    signingConfigs {
        release {
            if (project.hasProperty('android.signing.store.file')) {
                storeFile file(project.property('android.signing.store.file'))
                storePassword project.property('android.signing.store.password')
                keyAlias project.property('android.signing.key.alias')
                keyPassword project.property('android.signing.key.password')
            }
        }
    }
    
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

### Setting Up Android Signing

1. **Generate or prepare your keystore**:
```bash
# Generate new keystore
keytool -genkey -v -keystore my-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias my-key-alias

# Or use existing keystore
```

2. **Upload keystore to Secret Manager**:
```bash
gcloud secrets versions add android-keystore --data-file=my-release-key.jks
```

3. **Configure keystore properties**:
```bash
# Set via Terraform variables (recommended for automation)
terraform apply -var="keystore_password=your_password" -var="key_password=your_key_password" -var="key_alias=your_alias"

# Or manually add to Secret Manager
echo "storePassword=your_password
keyPassword=your_key_password
keyAlias=your_alias
storeFile=/workspace/keystore.jks" | gcloud secrets versions add keystore-properties --data-file=-
```

## Configuration Options

### Build Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `machine_type` | Cloud Build machine type | `E2_HIGHCPU_8` |
| `disk_size_gb` | Build disk size | `100` |
| `build_timeout` | Build timeout | `1200s` |
| `gradle_max_workers` | Gradle parallel workers | `4` |
| `gradle_memory` | Gradle JVM memory | `4g` |

### Android Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `android_compile_sdk` | Android compile SDK version | `34` |
| `android_min_sdk` | Android minimum SDK version | `21` |
| `android_target_sdk` | Android target SDK version | `34` |
| `gradle_version` | Gradle version | `8.2` |
| `java_version` | Java version | `17` |

### Feature Toggles

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_signing` | Enable APK signing | `false` |
| `enable_unit_tests` | Run unit tests | `true` |
| `enable_lint` | Run lint checks | `true` |
| `enable_monitoring` | Enable monitoring | `true` |
| `enable_cost_optimization` | Use cost-optimized features | `true` |

## Monitoring and Alerting

### Accessing Dashboards

After deployment, access your monitoring resources:

```bash
# Get dashboard URL
terraform output console_monitoring_url

# View build history
terraform output console_build_history_url
```

### Key Metrics

- **Build Success Rate**: Percentage of successful builds
- **Build Duration**: Time taken for complete builds
- **Storage Usage**: Artifact and cache storage consumption
- **Cost Tracking**: Build costs and quota usage

### Setting Up Alerts

The pipeline automatically creates alerts for:
- Build failures
- Long build times (>30 minutes)
- Budget thresholds (80%, 90%, 100%)

## Build Pipeline Details

### Build Steps

1. **Source Download**: Downloads source code from Cloud Storage
2. **Cache Extraction**: Restores Gradle cache for faster builds
3. **Secret Retrieval**: Gets signing credentials from Secret Manager
4. **Unit Tests**: Runs Android unit tests (if enabled)
5. **Lint Checks**: Performs code quality analysis (if enabled)
6. **Debug Build**: Builds debug APK
7. **Release Build**: Builds signed release APK (if signing enabled)
8. **Artifact Upload**: Stores build outputs in Cloud Storage
9. **Notifications**: Sends webhook notifications
10. **Cache Save**: Updates build cache for future builds

### Build Artifacts

After successful builds, find your artifacts at:
- **APK Files**: `gs://PROJECT_ID-build-artifacts/BUILD_ID/outputs/apk/`
- **Build Logs**: `gs://PROJECT_ID-build-artifacts/BUILD_ID/build_info.txt`
- **Test Reports**: `gs://PROJECT_ID-build-artifacts/BUILD_ID/outputs/reports/`

## Cost Optimization

### Implemented Optimizations

1. **Worker Pools**: Use cost-optimized machine types
2. **Caching**: Aggressive caching reduces build times by 60-80%
3. **Lifecycle Policies**: Automatic cleanup of old artifacts
4. **Resource Scaling**: Right-sized compute resources

### Cost Monitoring

```bash
# View current costs
gcloud billing projects describe $PROJECT_ID --billing-account=$BILLING_ACCOUNT_ID

# Set up budget alerts
terraform apply -var="billing_account_id=YOUR_BILLING_ACCOUNT_ID"
```

## Troubleshooting

### Common Issues

**Build Timeouts**
```bash
# Increase timeout
terraform apply -var="build_timeout=2400s"
```

**Out of Memory Errors**
```bash
# Increase machine type and memory
terraform apply -var="machine_type=E2_HIGHMEM_8" -var="gradle_memory=6g"
```

**Signing Issues**
```bash
# Verify keystore secret
gcloud secrets versions access latest --secret="android-keystore" > test-keystore.jks
file test-keystore.jks  # Should show Java KeyStore
```

**Cache Issues**
```bash
# Clear build cache
gsutil rm gs://PROJECT_ID-build-cache/cache.tgz
```

### Debug Build Issues

1. **Check Build Logs**:
```bash
# Get latest build ID
BUILD_ID=$(gcloud builds list --limit=1 --format="value(id)")

# View detailed logs
gcloud builds log $BUILD_ID
```

2. **Inspect Build Artifacts**:
```bash
# List build outputs
gsutil ls gs://PROJECT_ID-build-artifacts/$BUILD_ID/

# Download build info
gsutil cp gs://PROJECT_ID-build-artifacts/$BUILD_ID/build_info.txt .
```

3. **Test Locally**:
```bash
# Download and test source
gsutil cp gs://PROJECT_ID-source-uploads/your-app.zip .
unzip your-app.zip
./gradlew assembleDebug
```

## Security Considerations

### Secret Management
- All sensitive data stored in Secret Manager
- Automatic secret rotation supported
- Audit logging for all secret access

### Network Security
- Build environments are isolated
- No external network access during builds (optional)
- VPC integration available

### IAM Best Practices
- Dedicated service account for builds
- Principle of least privilege
- Regular access reviews recommended

## Maintenance

### Regular Tasks

1. **Update Android SDK**:
```bash
# Update builder image
terraform apply -var="android_compile_sdk=35"
```

2. **Clean Up Old Artifacts**:
```bash
# Lifecycle policies handle this automatically
# Manual cleanup if needed:
gsutil -m rm -r gs://PROJECT_ID-build-artifacts/older-than-90-days/
```

3. **Monitor Costs**:
```bash
# Review monthly costs
gcloud billing projects describe $PROJECT_ID --billing-account=$BILLING_ACCOUNT_ID
```

### Updates and Upgrades

```bash
# Update Terraform modules
terraform init -upgrade

# Apply updates
terraform plan
terraform apply
```