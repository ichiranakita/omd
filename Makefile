SHELL = /bin/bash
include Makefile.omd

DESTDIR ?=$(shell pwd)/destdir
RPM_TOPDIR=$$(pwd)/rpm.topdir
DPKG_TOPDIR=$$(pwd)/dpkg.topdir
SOURCE_TGZ=omd-$(OMD_VERSION).tar.gz
BIN_TGZ=omd-bin-$(OMD_VERSION).tar.gz
NEWSERIAL=$$(($(OMD_SERIAL) + 1))
APACHE_NAME=$(notdir $(APACHE_INIT))

.PHONY: install-global
# You can select a subset of the packages by overriding this
# variale, e.g. make PACKAGES='nagios rrdtool' pack
PACKAGES = *

omd: build

build:
	@set -e ; cd packages ; for p in $(PACKAGES) ; do \
	    $(MAKE) -C $$p build ; \
        done

pack:
	rm -rf $(DESTDIR)
	mkdir -p $(DESTDIR)$(OMD_PHYSICAL_BASE)
	A="$(OMD_PHYSICAL_BASE)" ; ln -s $${A:1} $(DESTDIR)/omd
	@set -e ; cd packages ; for p in $(PACKAGES) ; do \
            $(MAKE) -C $$p DESTDIR=$(DESTDIR) install ; \
            for hook in $$(cd $$p ; ls *.hook 2>/dev/null) ; do \
                mkdir -p $(DESTDIR)$(OMD_ROOT)/lib/omd/hooks ; \
                install -m 755 $$p/$$hook $(DESTDIR)$(OMD_ROOT)/lib/omd/hooks/$${hook%.hook} ; \
            done ; \
        done

	# Repair packages that install with silly modes (such as Nagios)
	chmod -R o+Xr $(DESTDIR)$(OMD_ROOT)
	$(MAKE) install-global

	# Install skeleton files (subdirs skel/ in packages' directories)
	mkdir -p $(DESTDIR)$(OMD_ROOT)/skel
	@set -e ; cd packages ; for p in $(PACKAGES) ; do \
            if [ -d "$$p/skel" ] ; then  \
              tar cf - -C $$p/skel --exclude="*~" --exclude=".gitignore" . | tar xvf - -C $(DESTDIR)$(OMD_ROOT)/skel ; \
            fi ;\
            $(MAKE) SKEL=$(DESTDIR)$(OMD_ROOT)/skel -C $$p skel ;\
        done

        # Create permissions file for skel
	mkdir -p $(DESTDIR)$(OMD_ROOT)/share/omd
	@set -e ; cd packages ; for p in $(PACKAGES) ; do \
	    if [ -e $$p/skel.permissions ] ; then \
	        echo "# $$p" ; \
	        cat $$p/skel.permissions ; \
	    fi ; \
	done > $(DESTDIR)$(OMD_ROOT)/share/omd/skel.permissions

        # Make sure, all permissions in skel are set to 0755, 0644
	failed=$$(find $(DESTDIR)$(OMD_ROOT)/skel -type d -not -perm 0755) ; \
	if [ -n "$$failed" ] ; then \
	    echo "Invalid permissions for skeleton dirs. Must be 0755:" ; \
            echo "$$failed" ; \
            exit 1 ; \
        fi
	failed=$$(find $(DESTDIR)$(OMD_ROOT)/skel -type f -not -perm 0644) ; \
	if [ -n "$$failed" ] ; then \
	    echo "Invalid permissions for skeleton files. Must be 0644:" ; \
            echo "$$failed" ; \
            exit 1 ; \
        fi

	# Fix packages which did not add ###ROOT###
	find $(DESTDIR)$(OMD_ROOT)/skel -type f | xargs -n1 sed -i -e 's+$(OMD_ROOT)+###ROOT###+g'

	# Remove site-specific directories that went under /omd/version
	rm -rf $(DESTDIR)/{var,tmp}

	# Pack the whole stuff into a tarball
	tar czf $(BIN_TGZ) --owner=root --group=root -C $(DESTDIR) .

clean:
	rm -rf $(DESTDIR)
	@for p in packages/* ; do \
            $(MAKE) -C $$p clean ; \
        done

mrproper:
	git clean -xfd


# Create installations files that do not lie beyond /omd/versions/$(OMD_VERSION)
# and files not owned by a specific package.
install-global:
	# Create link to default version
	ln -s $(OMD_VERSION) $(DESTDIR)$(OMD_BASE)/versions/default

	# Create global symbolic links. Those links are share between
	# all installed versions and refer to the default version.
	mkdir -p $(DESTDIR)/usr/bin
	ln -sfn /omd/versions/default/bin/omd $(DESTDIR)/usr/bin/omd
	mkdir -p $(DESTDIR)/usr/share/man/man8
	ln -sfn /omd/versions/default/share/man/man8/omd.8.gz $(DESTDIR)/usr/share/man/man8/omd.8.gz
	mkdir -p $(DESTDIR)/etc/init.d
	ln -sfn /omd/versions/default/share/omd/omd.init $(DESTDIR)/etc/init.d/omd
	mkdir -p $(DESTDIR)$(APACHE_CONF_DIR)
	ln -sfn /omd/versions/default/share/omd/apache.conf $(DESTDIR)$(APACHE_CONF_DIR)/zzz_omd.conf

	# Base directories below /omd
	mkdir -p $(DESTDIR)$(OMD_BASE)/sites
	mkdir -p $(DESTDIR)$(OMD_BASE)/apache


	# Information about distribution and OMD
	mkdir -p $(DESTDIR)$(OMD_ROOT)/share/omd
	install -m 644 distros/Makefile.$(DISTRO_NAME)_$(DISTRO_VERSION) $(DESTDIR)$(OMD_ROOT)/share/omd/distro.info
	echo -e "OMD_VERSION = $(OMD_VERSION)\nOMD_PHYSICAL_BASE = $(OMD_PHYSICAL_BASE)" > $(DESTDIR)$(OMD_ROOT)/share/omd/omd.info


# Create source tarball. This currently only works in a checked out GIT 
# repository.
$(SOURCE_TGZ) dist:
	rm -rf omd-$(OMD_VERSION)
	mkdir -p omd-$(OMD_VERSION)
	git archive HEAD | tar xf - -C omd-$(OMD_VERSION)
	tar czf $(SOURCE_TGZ) omd-$(OMD_VERSION)
	rm -rf omd-$(OMD_VERSION)


# Build RPM from source code. This currently needs 'make dist' and thus only
# works within a GIT repository.
rpm:
	sed -e 's/^Requires:.*/Requires:	$(OS_PACKAGES)/' \
            -e 's/%{version}/$(OMD_VERSION)/g' \
            -e 's/^Release:.*/Release: $(DISTRO_CODE).$(OMD_SERIAL)/' \
	    -e 's#@APACHE_CONFDIR@#$(APACHE_CONF_DIR)#g' \
	    -e 's#@APACHE_NAME@#$(APACHE_NAME)#g' \
	    omd.spec.in > omd.spec
	rm -f $(SOURCE_TGZ)
	$(MAKE) $(SOURCE_TGZ)
	mkdir -p $(RPM_TOPDIR)/{SOURCES,BUILD,RPMS,SRPMS,SPECS}
	cp $(SOURCE_TGZ) $(RPM_TOPDIR)/SOURCES
	rpmbuild -ba --define "_topdir $(RPM_TOPDIR)" \
             --buildroot=$$(pwd)/rpm.buildroot omd.spec
	mv -v $(RPM_TOPDIR)/RPMS/*/*.rpm .
	mv -v $(RPM_TOPDIR)/SRPMS/*.src.rpm .
	rm -rf $(RPM_TOPDIR) rpm.buildroot

# Build DEB from prebuild binary. This currently needs 'make dist' and thus only
# works within a GIT repository.
deb-environment:
	@if test -z "$(DEBFULLNAME)" || test -z "$(DEBEMAIL)"; then \
	  echo "please read 'man dch' and set DEBFULLNAME and DEBEMAIL" ;\
	  exit 1; \
	fi

# newversion means new OMD version
deb-newversion: deb-environment
	dch --package omd-$(OMD_VERSION) \
	    --newversion $(OMD_VERSION)build1 \
            -b \
	    --distributor 'unstable' "new upstream version"

# incrementing debian packaging version (same OMD version)
deb-incversion: deb-environment
	dch -i --no-auto-nmu --distributor 'unstable'

deb: 
	sed -e 's/###OMD_VERSION###/$(OMD_VERSION)/' \
	   `pwd`/debian/control.in > `pwd`/debian/control
	fakeroot debian/rules clean
	debuild --no-lintian -i\.git -I\.git \
			-iomd-bin-$(OMD_VERSION).tar.gz \
			-Iomd-bin-$(OMD_VERSION).tar.gz \
			-i.gitignore -I.gitignore \
			-uc -us -rfakeroot
	# -- renaming deb package to DISTRO_CODE dependend name
	arch=`dpkg-architecture -qDEB_HOST_ARCH` ; \
	build=`sed -e '1s/.*(\(.*\)).*/\1/;q' debian/changelog` ; \
	distro=`echo $$build | sed -e 's/build/$(DISTRO_CODE)/' ` ; \
	echo "$$arch $$build $$distro"; \
	mv "../omd-$(OMD_VERSION)_$${build}_$${arch}.deb" \
	   "../omd-$(OMD_VERSION)_$${distro}_$${arch}.deb" ;

# Only to be used for developement testing setup 
setup: pack xzf

# Only for development: install tarball below /
xzf:
	tar xzf $(BIN_TGZ) -C / # HACK: Add missing suid bits if compiled as non-root
	chmod 4755 $(OMD_ROOT)/lib/nagios/plugins/check_{icmp,dhcp}
	$(APACHE_CTL) -k graceful
	


version:
	@newversion=$$(dialog --stdout --inputbox "New Version:" 0 0 "$(OMD_VERSION)") ; \
	if [ -n "$$newversion" ] && [ "$$newversion" != "$(OMD_VERSION)" ]; then \
	    sed -ri 's/^(OMD_VERSION[[:space:]]*= *).*/\1'"$$newversion/" Makefile.omd ; \
	    sed -ri 's/^(OMD_SERIAL[[:space:]]*= *).*/\1'"$(NEWSERIAL)/" Makefile.omd ; \
	    sed -ri 's/^(OMD_VERSION[[:space:]]*= *).*/\1"'"$$newversion"'"/' packages/omd/omd ; \
	    make deb-newversion ; \
	fi ;
