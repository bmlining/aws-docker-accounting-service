#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $0); pwd -P)
DOCKER_FILE="${SCRIPT_DIR}/Dockerfile"

DOCKER_REGISTRY=hub.docker.com/r
TAG=bmlining/aws-docker-accounting-service

JAVA_TAG="jeanblanchard/java:8"

export HOME="${SCRIPT_DIR}/home"

SCRATCH_DIR=$(mktemp -d accounting-docker.XXXXXXXXXX)

docker_build()
{
	docker build -f "${DOCKER_FILE}" --rm=true -t "${TAG}" "${SCRIPT_DIR}"
	if [ $? -ne 0 ] ; then
		echo "Build of docker image failed"
		exit 1
	fi
}

docker_publish()
{
	docker tag -f "${TAG}" "${DOCKER_REGISTRY}/${TAG}"
	if [ $? -ne 0 ] ; then
		echo "Tag of docker image failed"
		exit 1
	fi

	docker push "${DOCKER_REGISTRY}/${TAG}"
	if [ $? -ne 0 ] ; then
		echo "Push of docker image failed"
		exit 1
	fi
}

docker_test()
{
	
}

wait_for_url()
{
	local url="${1}"

	for i in {1..30} ; do
		curl -s -f --noproxy '*' "${url}"
		if [ $? == 0 ]; then
			return 0
		fi
		sleep 1
	done

	return 1
}

cleanup()
{

}

trap cleanup SIGHUP SIGINT SIGTERM EXIT

docker_build
#docker_test || exit 1

if [ "${NO_PUBLISH}" != "true" ]; then
	docker_publish
fi

exit 0
