#!/bin/sh

cd /opt/accounting

java \
	-jar /opt/accounting/lib/accounting-service.jar \
	server \
	/opt/accounting/conf/accounting-service-config.yml

exit $?
