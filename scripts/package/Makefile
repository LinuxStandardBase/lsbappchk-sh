# XXX We should play the usual tricks defining stuff here and building
# XXX a specfile from this info, but not yet: for now keep in sync
PACKAGE=lsb-appchk-shell
VERSION=4.0.0
RELEASE=1

#
# Derive date string for daily snapshots
ISO_DATE=$(shell date +"%Y%m%d")
PWD=$(shell pwd)

FULL_PACKAGE_NAME=$(PACKAGE)-$(VERSION)
DOC_DIR=/opt/lsb/test/doc
RPM_BINARY_NAME=$(FULL_PACKAGE_NAME)-$(RELEASE).$(RPM_BUILD_ARCH).rpm
RPM_SOURCE_NAME=$(FULL_PACKAGE_NAME)-$(RELEASE).src.rpm

SOURCE1 = $(PACKAGE)-$(VERSION).tar.gz

# Temporary build directory
TMP_BUILD_DIR=/tmp/$(FULL_PACKAGE_NAME)

# Handle different version generation for snapshots than for official builds
# OFFICIAL_RELEASE should be set to the tag to extract from CVS
ifdef OFFICIAL_RELEASE
VERSION_SUFFIX=
# EXPORT_TAG should be set to the cvs tag to use
EXPORT_TAG=-r $(OFFICIAL_RELEASE)
else
VERSION_SUFFIX=.$(ISO_DATE)
EXPORT_TAG=-D now
endif

# Determine whether to use rpm or rpmbuild to build the packages
ifeq ($(wildcard /usr/bin/rpmbuild),)
	RPM_BUILD_CMD=rpm
else
	RPM_BUILD_CMD=rpmbuild 
endif

# Get RPM configuration information
# NOTE THAT RPM_TMP_BUILD_DIR IS DELETED AFTER THE RPM BUILD IS COMPLETED
# The rpmrc file translates targets where there are multiple choices per
# architecture. On build, the derived RPM_BUILD_ARCH is given as the target
RCFILELIST="/usr/lib/rpm/rpmrc:./rpmrc"
RPM_TMP_BUILD_DIR=$(HOME)/tmp/rpm-build
# noarch package
#RPM_BUILD_ARCH=$(shell rpm --rcfile ${RCFILELIST} --eval=%{_target_cpu})
#RPM_BINARY_DIR=$(RPM_TMP_BUILD_DIR)/RPMS/$(RPM_BUILD_ARCH)
RPM_BUILD_ARCH=noarch
RPM_BINARY_DIR=$(RPM_TMP_BUILD_DIR)/RPMS/noarch
RPM_SRPM_DIR=$(RPM_TMP_BUILD_DIR)/SRPMS

# Override this on the command line to use a different repo
BZRTREES?=http://bzr.linux-foundation.org/lsb/devel
BZR_MODULE=lsbappchk-sh

# Default target
ifndef BUILD_NO_DEB
all: rpm_package deb_package
else
all: rpm_package
endif

clean:
	@rm -f *.rpm *.deb *.tar.gz

tarball: $(SOURCE1)

deb_package: rpm_package
	@fakeroot alien -cdk $(RPM_BINARY_NAME)

list_uploadable:
	@echo $(RPM_BINARY_NAME)
ifndef BUILD_NO_DEB
	@ls *.deb
endif

rpm_package: $(PACKAGE).spec tarball 
	@mkdir -p $(RPM_TMP_BUILD_DIR)/BUILD
	@mkdir -p $(RPM_TMP_BUILD_DIR)/RPMS
	@mkdir -p $(RPM_TMP_BUILD_DIR)/SRPMS
ifdef SIGN_PACKAGES
	@expect -c 'set timeout -1' -c 'spawn $(RPM_BUILD_CMD) --sign --rcfile ${RCFILELIST} --define=_sourcedir\ $(PWD) --define=_topdir\ $(RPM_TMP_BUILD_DIR) --define=_target_cpu\ $(RPM_BUILD_ARCH) --define=rel\ $(RELEASE) --define=version\ $(VERSION) -ba $(PACKAGE).spec' -c 'expect -ex "Enter pass phrase:"' -c 'send "\n"' -c 'expect "Executing(%clean)"' -c 'expect "exit 0"' -c 'send "\n"'
else
	@$(RPM_BUILD_CMD) --rcfile ${RCFILELIST} --define="_sourcedir $(PWD)" --define="_topdir $(RPM_TMP_BUILD_DIR)" --define="_target_cpu $(RPM_BUILD_ARCH)" --define="rel $(RELEASE)" --define="version $(VERSION)" -ba $(PACKAGE).spec
endif
	@mv $(RPM_SRPM_DIR)/$(RPM_SOURCE_NAME) .
	@mv $(RPM_BINARY_DIR)/$(RPM_BINARY_NAME) .
	@rm -rf $(RPM_TMP_BUILD_DIR)

$(SOURCE1):
ifdef CVSTREES
	cvs export $(EXPORT_TAG) $(CVSTREES)
	cd $(CVSTREES) && make gensrc
	mv $(CVSTREES) $(FULL_PACKAGE_NAME)
	tar czf $(SOURCE1) $(FULL_PACKAGE_NAME)
	@rm -rf $(FULL_PACKAGE_NAME)
	# Remove CVSTREES
	@rm -rf `echo '$(CVSTREES)' | sed 's/\/.*//'`
else
	bzr export $(SOURCE1) $(BZRTREES)/$(BZR_MODULE)
endif

.PHONY : tarball rpm_package
