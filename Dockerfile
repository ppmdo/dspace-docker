FROM centos:7
MAINTAINER pablop@almat.com.mx

ENV DSPACE_VERSION=5.5 TOMCAT_MAJOR=8 TOMCAT_VERSION=8.5.12
ENV TOMCAT_TGZ_URL=https://archive.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz \
    MAVEN_TGZ_URL=https://www.apache.org/dist/maven/maven-3/3.5.2/binaries/apache-maven-3.5.2-bin.tar.gz \
    DSPACE_TGZ_URL=https://github.com/DSpace/DSpace/releases/download/dspace-${DSPACE_VERSION}/dspace-${DSPACE_VERSION}-release.tar.gz \
    DSPACE_THEME=custom_theme \
    DSPACE_CUSTOM_TGZ_URL=http://updates_server/update.tar.xz


ENV CATALINA_HOME=/opt/tomcat DSPACE_HOME=/opt/dspace
ENV PATH=$CATALINA_HOME/bin:$DSPACE_HOME/bin:/opt/maven/bin:$PATH

## SYSTEMD - Taken from: https://hub.docker.com/r/centos/systemd/~/dockerfile/
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
rm -f /lib/systemd/system/multi-user.target.wants/*;\
rm -f /etc/systemd/system/*.wants/*;\
rm -f /lib/systemd/system/local-fs.target.wants/*; \
rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
rm -f /lib/systemd/system/basic.target.wants/*;\
rm -f /lib/systemd/system/anaconda.target.wants/*;

VOLUME [ "/sys/fs/cgroup" ]

CMD ["/usr/sbin/init"]

WORKDIR /tmp

RUN mkdir /opt/tomcat \
    && mkdir /opt/maven \
    && mkdir /opt/dspace

## DEPENDENCIES
RUN yum update -y \
    && yum install -y java-1.7.0-openjdk-devel which ant git ruby-devel
RUN echo "$TOMCAT_TGZ_URL" && curl -fSL --insecure "$TOMCAT_TGZ_URL" -o tomcat.tar.gz 
RUN curl -fSL --insecure "$MAVEN_TGZ_URL" -o maven.tar.gz 
RUN curl -L --insecure "$DSPACE_TGZ_URL" -o dspace.tar.xz 

RUN tar -xvf tomcat.tar.gz --strip-components=1 -C "$CATALINA_HOME" 
RUN tar -xvf maven.tar.gz --strip-components=1  -C /opt/maven 
RUN tar -xvf dspace.tar.xz  

RUN useradd dspace && chown -Rv dspace: /tmp/dspace*

#CUSTOMIZATION
WORKDIR /tmp/dspace-${DSPACE_VERSION}-release
USER dspace

RUN if [ $(echo ${DSPACE_VERSION} | cut -c 1)  = 6 ]; \
    then cp dspace/config/local.cfg.EXAMPLE dspace/config/local.cfg \
    && sed -i 's/dspace.dir=\/dspace/dspace.dir=\/opt\/dspace\//' dspace/config/local.cfg \
    && sed -i 's/localhost:5432/db:5432/' dspace/config/local.cfg ; \
    fi

RUN if [ $(echo ${DSPACE_VERSION} | cut -c 1)  = 5 ]; \
    then sed -i 's/dspace.install.dir=\/dspace/dspace.install.dir=\/opt\/dspace\//' build.properties \
    && sed -i 's/localhost:5432/db:5432/' build.properties; \
    fi

RUN sed 's/<theme name="Atmire Mirage Theme" regex=".*" path="Mirage\/" \/>/<!--<theme name="Atmire Mirage Theme" regex=".*" path="Mirage\/" \/>-->/' -i dspace/config/xmlui.xconf
RUN sed "/<\/themes>/ i\<theme name=\"CUSTOM THEME\" regex=\".*\" path=\"$DSPACE_THEME\/\" \/>" -i dspace/config/xmlui.xconf

#COMPILATION
RUN mvn dependency:resolve
RUN mvn package -Dmirage2.on=true

USER root

#INSTALLATION
RUN cd dspace/target/dspace-installer \
    && ant init_installation init_configs install_code copy_webapps

## STARTUP
RUN mkdir -p /opt/tomcat/conf/Catalina/localhost/
RUN echo -e 'STR="<?xml version=\"1.0\"?> \n<Context\ndocBase=\"/opt/dspace/webapps/$@\"\nreloadable=\"true\"\ncachingAllowed=\"false\"/>"\necho "$STR"' > deployer.sh
RUN for i in xmlui jspui sword swordv2 rest oai; do sh deployer.sh $i > /opt/tomcat/conf/Catalina/localhost/$i.xml; done

WORKDIR /opt/dspace
RUN rm -rf webapps solr lib config

WORKDIR /opt/temp
RUN curl -fSL --insecure "$DSPACE_CUSTOM_TGZ_URL" -o dspace_custom.tar.xz
RUN tar -xzvf dspace_custom.tar.xz
RUN mv dspace/webapps ../dspace/
RUN mv dspace/config ../dspace/
RUN mv dspace/lib ../dspace/
RUN mv dspace/solr ../dspace/

WORKDIR /opt/dspace
RUN sed -i 's/localhost:5432/db:5432/' config/dspace.cfg
RUN chown -R dspace: .

EXPOSE 8080

ENTRYPOINT ["/opt/tomcat/bin/catalina.sh", "run"]
