FROM jeanblanchard/busybox-java:8

MAINTAINER brian.lininger@gmail.com

RUN \
	mkdir -p /opt/service/bin && \
	mkdir -p /opt/service/lib && \
	mkdir -p /opt/service/conf && \
	mkdir -p /opt/service/logs
	
VOLUME /opt/service/conf
VOLUME /opt/service/logs

EXPOSE 8080 8081
