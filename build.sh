#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $0); pwd -P)

DOCKER_REGISTRY=hub.docker.com
TAG=bmlining/aws-accounting-service

JAVA_TAG="jeanblanchard/busybox-java:8"

export HOME="${SCRIPT_DIR}/home"

SCRATCH_DIR=$(mktemp -d catalog-docker.XXXXXXXXXX)

docker_build()
{
	docker build -f "${SCRATCH_DIR}/Dockerfile" --rm=true "--no-cache=${NO_CACHE}" -t "${TAG}" "${SCRIPT_DIR}"
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
	local test_type=$1
	local host_port=$2
	local url="http://${host_port}/v1/services/"
	local url_category="http://${host_port}/v1/categories/"

	local response_headers_file=$(mktemp --tmpdir=${SCRATCH_DIR} -t create_sm_response.XXXXXXXXXX)
    # Create the root category
	curl --noproxy '*' -v -f -i \
	-D "${response_headers_file}" \
	-H "Content-Type: application/json" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer this_is_a_fake_read_write_token" \
	-X "POST" \
	-d "${SERVICE_CATEGORY_ROOT_JSON}" \
	"${url_category}"

    # Create the test category
	curl --noproxy '*' -v -f -i \
	-D "${response_headers_file}" \
	-H "Content-Type: application/json" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer this_is_a_fake_read_write_token" \
	-X "POST" \
	-d "${SERVICE_CATEGORY_TEST_JSON}" \
	"${url_category}"

	# Create Service Metadata
	curl --noproxy '*' -v -f -i \
	-D "${response_headers_file}" \
	-H "Content-Type: application/json" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer this_is_a_fake_read_write_token" \
	-X "POST" \
	-d "${SERVICE_METATA_JSON}" \
	"${url}"

	if [ $? -ne 0 ] ; then
		echo "Create of new service metadata failed"
		return $?
	fi

    local created_sm_url=$(egrep '^Location:' ${response_headers_file} | sed -e 's%Location: *%%g' | tr '[:space:]' ' ' | sed -e 's% *$%%g')
	echo -n "${created_sm_url}" > "${SCRATCH_DIR}/created_sm_${test_type}"
	# Retrieve it back
	curl --noproxy '*' -v -f -i \
	-H "Accept: application/json" \
	-X "GET" \
	"${created_sm_url}"

	if [ $? -ne 0 ] ; then
		echo "Retrieve of newly created service metadata failed"
		return 1
	fi

	return 0
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

docker_test_memory()
{
	local container=$(docker run -P -d --name="${CATALOG_MEM_CONTAINER_NAME}" "${TAG}")
	if [ $? -ne 0 ]; then
		echo "Cannot start docker container ${TAG}"
		exit 1
	fi
	local host_port=$(docker port "${container}" 8080/tcp | sed -e 's%0\.0\.0\.0%localhost%')
	if [ $? -ne 0 ]; then
		echo "Cannot determine docker port for container ${container}"
		exit 1
	fi

	local api_docs_url="http://${host_port}/api-docs/"
	wait_for_url "${api_docs_url}"
	if [ $? -ne 0 ]; then
		echo "URL ${api_docs_url} never became available for docker container ${container}"
		exit 1
	fi

	docker_test "memory" "${host_port}"
	if [ $? -ne 0 ]; then
		echo "Tests failed"
		exit 1
	fi

	docker stop "${container}"
	docker rm -v "${container}"

	return 0
}

docker_test_elasticsearch()
{
	# Pull the elasticsearch image
	docker pull $ES_TAG
   	if [ $? -ne 0 ] ; then
   		echo "Pull of Java base image failed"
   		exit 1
   	fi

	# Start Elasticsearch Container
	local es_container=$(docker run -P -d --name="${ES_CONTAINER_NAME}" "${ES_TAG}")
	if [ $? -ne 0 ]; then
		echo "Cannot start docker container ${ES_TAG}"
		exit 1
	fi
	local es_host_port=$(docker port "${es_container}" 9200/tcp | sed -e "s%0\.0\.0\.0%$(hostname -f)%")
	if [ $? -ne 0 ]; then
		echo "Cannot determine docker port for container ${es_container}"
		exit 1
	fi

	local es_url="http://${es_host_port}/"
	wait_for_url "${es_url}"
	if [ $? -ne 0 ]; then
		echo "URL ${es_url} never became available for docker container ${es_container}"
		exit 1
	fi

	# Start Catalog Service Container - Wired to Elasticsearch
	local container=$(docker run -P -d --name="${CATALOG_ES_CONTAINER_NAME}" -e "CATALOG_STORE=ELASTICSEARCH" -e "ELASTICSEARCH_URL=${es_url}" "${TAG}")
	if [ $? -ne 0 ]; then
		echo "Cannot start docker container ${TAG}"
		exit 1
	fi
	local host_port=$(docker port "${container}" 8080/tcp | sed -e 's%0\.0\.0\.0%localhost%')
	if [ $? -ne 0 ]; then
		echo "Cannot determine docker port for container ${container}"
		exit 1
	fi

	local api_docs_url="http://${host_port}/api-docs/"
	wait_for_url "${api_docs_url}"
	if [ $? -ne 0 ]; then
		echo "URL ${api_docs_url} never became available for docker container ${container}"
		exit 1
	fi

	# Make some calls to the catalog service
	docker_test "elasticsearch" "${host_port}"
	if [ $? -ne 0 ]; then
		echo "Tests failed"
		exit 1
	fi

	# Validate the data got to Elasticsearch
	local created_sm_url="$(cat ${SCRATCH_DIR}/created_sm_elasticsearch)"
	# Derive elasticearch URL from catalog service URL
	# e.g. http://localhost:8080/v1/services/ServiceMetadata/namespace/name/version => http://localhost:9200/catalog/ServiceMetadata/namespace~name~version
	local created_sm_es_url="${es_url}catalog/ServiceMetadata/$(echo -n ${created_sm_url} | sed -e 's%/$%%g' -e 's%.*/v1/services/%%g' -e 's%/%~%g')"
	wait_for_url "${created_sm_es_url}"
	if [ $? -ne 0 ]; then
		echo "URL ${created_sm_es_url} never became available for docker container ${es_container}"
		exit 1
	fi

	docker stop "${container}"
	docker rm -v "${container}"

	docker stop "${es_container}"
	docker rm -v "${es_container}"

	return 0
}

cleanup()
{
	for container in "${CATALOG_MEM_CONTAINER_NAME}" "${CATALOG_ES_CONTAINER_NAME}" "${ES_CONTAINER_NAME}" ; do
		echo "Killing and removing container ${container}"
		docker logs "${container}"
		docker kill "${container}"
		docker rm -v "${container}"
	done

	# Delete all untagged images.
	local dangling_images=$(docker images -q -f dangling=true)
	if [ "" != "${dangling_images}" ] ; then
		printf "\n>>> Deleting untagged images\n\n" && docker rmi ${dangling_images}
	fi

	# Remove scratch directory
	rm -rf "${SCRATCH_DIR}"
}

trap cleanup SIGHUP SIGINT SIGTERM EXIT

docker_build
#docker_test || exit 1

if [ "${NO_PUBLISH}" != "true" ]; then
	docker_publish
fi

exit 0
