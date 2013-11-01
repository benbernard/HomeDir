#!/bin/bash

mkdir -p /opt/local/bin/RecordStream
pushd /opt/local/bin/RecordStream

apt-get -y install ia32-libs

if ! curl https://s3.amazonaws.com/breadcrumb.install/recs.tar.gz > recs.tar.gz; then
    echo "Failed to download the RecordStream package"
    exit 1
fi

rm -rf RecordStream

tar xzf recs.tar.gz
rm recs.tar.gz

for i in `ls RecordStream/bin`; do ln -sf /opt/local/bin/RecordStream/RecordStream/bin/$i /usr/local/bin/$i; done

popd
