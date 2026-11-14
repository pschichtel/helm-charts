-- Roles + databases for every component in this stack (created once, on first init)
CREATE ROLE "unifi-core" LOGIN;
CREATE DATABASE "unifi-core" OWNER "unifi-core";
CREATE ROLE "ulp-go" LOGIN;
CREATE DATABASE "ulp-go" OWNER "ulp-go";
CREATE DATABASE "ulp-go-syslog" OWNER "ulp-go";
CREATE ROLE "uid" LOGIN;
CREATE DATABASE "uid" OWNER "uid";
CREATE ROLE "unifi-directory" LOGIN;
CREATE DATABASE "unifi-directory" OWNER "unifi-directory";
CREATE ROLE "ucs-agent" LOGIN;
CREATE DATABASE "ucs-agent" OWNER "ucs-agent";
CREATE ROLE "unifi-identity-update" LOGIN;
CREATE DATABASE "unifi-identity-update" OWNER "unifi-identity-update";
CREATE ROLE "unifi" LOGIN;
CREATE DATABASE "unifi" OWNER "unifi";
