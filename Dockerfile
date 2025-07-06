FROM ubuntu:22.04
RUN apt-get update && apt-get install -y curl git unzip wget openjdk-17-jdk build-essential && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH=$PATH:$JAVA_HOME/bin
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools
RUN mkdir -p $ANDROID_HOME && cd $ANDROID_HOME && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-7583922_latest.zip && \
    unzip commandlinetools-linux-7583922_latest.zip && rm commandlinetools-linux-7583922_latest.zip && \
    mv cmdline-tools latest && mkdir cmdline-tools && mv latest cmdline-tools/
RUN yes | sdkmanager --licenses && sdkmanager --update && \
    sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34" "platforms;android-21"
RUN wget -q https://services.gradle.org/distributions/gradle-8.2-bin.zip && \
    unzip gradle-8.2-bin.zip && mv gradle-8.2 /opt/gradle && rm gradle-8.2-bin.zip
ENV PATH=$PATH:/opt/gradle/bin
WORKDIR /workspace