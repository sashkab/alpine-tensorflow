FROM alpine:3.10 as bazelbuild

# Based on https://github.com/tatsushid/docker-alpine-py3-tensorflow-jupyter/blob/master/Dockerfile
# Changes:
# - Bumping versions of Bazel and Tensorflow
# - Add -Xmx to the Java params when building Bazel
# - Disable TF_GENERATE_BACKTRACE and TF_GENERATE_STACKTRACE

ENV JAVA_HOME /usr/lib/jvm/default-jvm
ENV BAZEL_VERSION 0.25.2

RUN apk add --no-cache bash openjdk8 libarchive zip unzip coreutils git linux-headers protobuf python curl gcc g++


# RUN apk add --repository http://dl-cdn.alpinelinux.org/alpine/edge/community openjdk10

# Bazel download
RUN curl -SLO https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-dist.zip \
    && mkdir bazel-${BAZEL_VERSION} \
    && unzip -qd bazel-${BAZEL_VERSION} bazel-${BAZEL_VERSION}-dist.zip

# Bazel install https://github.com/davido/bazel-alpine-package/blob/master/APKBUILD
RUN cd bazel-${BAZEL_VERSION} \
    && EXTRA_BAZEL_ARGS=--host_javabase=@local_jdk//:jdk ./compile.sh \
    && cp -p output/bazel /usr/bin/ \
    && echo startup --server_javabase=$JAVA_HOME >> /etc/bazel.bazelrc

FROM alpine:3.10 as tensorflowbuild

COPY --from=bazelbuild /usr/bin/bazel /usr/bin/bazel
COPY --from=bazelbuild /etc/bazel.bazelrc  /etc/bazel.bazelrc

ENV JAVA_HOME /usr/lib/jvm/default-jvm
ENV TENSORFLOW_VERSION 1.14.0

# tf requirements
RUN apk add --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing hdf5-dev
RUN apk add --no-cache python3 python3-tkinter py3-numpy py3-numpy-f2py freetype libpng libjpeg-turbo imagemagick graphviz git

RUN apk add --no-cache --virtual=.build-deps \
        bash cmake curl freetype-dev g++ libjpeg-turbo-dev libpng-dev linux-headers make musl-dev openblas-dev openjdk8 patch perl \
        python3-dev py-numpy-dev rsync sed swig zip libbsd-dev \
        && cd /tmp \
        && python3 -mpip install --no-cache-dir -U wheel setuptools pip \
        && $(cd /usr/bin && ln -s python3 python)

# Download Tensorflow
RUN cd /tmp \
    && curl -SL https://github.com/tensorflow/tensorflow/archive/v${TENSORFLOW_VERSION}.tar.gz \
        | tar xzf -

# Build Tensorflow
RUN cd /tmp/tensorflow-${TENSORFLOW_VERSION} \
    && : musl-libc does not have "secure_getenv" function \
    && sed -i -e '/define TF_GENERATE_BACKTRACE/d' tensorflow/core/platform/default/stacktrace.h \
    && sed -i -e '/define TF_GENERATE_STACKTRACE/d' tensorflow/core/platform/stacktrace_handler.cc \
    && echo "#include <linux/sysctl.h>" >> /usr/include/sys/sysctl.h \
    && PYTHON_BIN_PATH=/usr/bin/python \
        PYTHON_LIB_PATH=/usr/lib/python3.7/site-packages \
        CC_OPT_FLAGS="-march=native" \
        TF_NEED_JEMALLOC=1 \
        TF_NEED_GCP=0 \
        TF_NEED_HDFS=0 \
        TF_NEED_S3=0 \
        TF_ENABLE_XLA=0 \
        TF_NEED_GDR=0 \
        TF_NEED_VERBS=0 \
        TF_NEED_OPENCL=0 \
        TF_NEED_CUDA=0 \
        TF_NEED_MPI=0 \
        bash configure
RUN cd /tmp/tensorflow-${TENSORFLOW_VERSION} \
        && bazel build --curses=yes --color=yes -c opt //tensorflow/tools/pip_package:build_pip_package
RUN cd /tmp/tensorflow-${TENSORFLOW_VERSION} \
    && ./bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg
RUN cp /tmp/tensorflow_pkg/tensorflow-${TENSORFLOW_VERSION}-cp37-cp37m-linux_x86_64.whl /root

# Make sure it's built properly
RUN pip3 install --no-cache-dir /root/tensorflow-${TENSORFLOW_VERSION}-cp37-cp37m-linux_x86_64.whl \
    && python3 -c 'import tensorflow'
