include ../../../Makefile.omd

NAME        = check_vmware_esx
VERSION     = master
DIR         = $(NAME)-$(VERSION)
SRC         = $(DIR).tar.gz

build:
	tar zxf $(SRC)
	for p in patches/*.patch ; do \
	    echo "applying $$p..." ; \
	    ( cd $(DIR) ; patch -p1 ) < $$p || exit 1; \
	done
	make -C "$(DIR)" check_vmware_esx

install:
	mkdir -p $(DESTDIR)$(OMD_ROOT)/lib/nagios/plugins
	install -m 755 $(DIR)/check_vmware_esx $(DESTDIR)$(OMD_ROOT)/lib/nagios/plugins
	mkdir -p $(DESTDIR)$(OMD_ROOT)/share/doc/check_vmware_esx
	install -m 755 install_vmware_sdk.sh $(DESTDIR)$(OMD_ROOT)/share/doc/check_vmware_esx

skel:

clean:
	rm -rf $(DIR)

update:
	wget "https://github.com/BaldMansMojo/check_vmware_esx/archive/master.tar.gz" -O check_vmware_esx-master.tar.gz
