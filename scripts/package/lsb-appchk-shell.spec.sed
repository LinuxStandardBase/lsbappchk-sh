# %{ver}, %{rel} are provided by the Makefile
%define ver @VERSION@
%define rel @RELEASE@
%define basedir /opt/lsb

Summary: LSB Shell Script Application Checker
Name: lsb-appchk-shell
Version: %{ver}
Release: %{rel}
License: GPL
Group: Development/Tools
Source: %{name}-%{version}.tar.gz
URL: http://www.linuxbase.org/test
BuildRoot: %{_tmppath}/%{name}-root
AutoReqProv: no
BuildArch: noarch
BuildRequires: perl(Parse::Eyapp) 

%description
This is the official package version of the LSB Shell Script Checker. 

#==================================================
%prep
%setup -q

#==================================================
%build
make

#==================================================
%install

rm -rf ${RPM_BUILD_ROOT}
mkdir -p ${RPM_BUILD_ROOT}%{basedir}/bin
mkdir -p ${RPM_BUILD_ROOT}%{basedir}/share/appchk
cp -p bin/lsbappchk-sh.pl ${RPM_BUILD_ROOT}%{basedir}/bin
chmod a+x ${RPM_BUILD_ROOT}%{basedir}/bin/lsbappchk-sh.pl 
cp -p share/appchk/ShParser.pm ${RPM_BUILD_ROOT}%{basedir}/share/appchk
cp -p share/appchk/sh-cmdlist-* ${RPM_BUILD_ROOT}%{basedir}/share/appchk

# License files
install -d ${RPM_BUILD_ROOT}%{basedir}/doc/%{name}
cp doc/lsb-appchk-sh/COPYING ${RPM_BUILD_ROOT}%{basedir}/doc/%{name}

#==================================================
%clean
if [ ! -z "${RPM_BUILD_ROOT}"  -a "${RPM_BUILD_ROOT}" != "/" ]; then 
    rm -rf ${RPM_BUILD_ROOT}
fi

#==================================================
%files
%defattr(-,root,root)

/opt/lsb/bin/lsbappchk-sh.pl
%dir /opt/lsb/share/appchk
/opt/lsb/share/appchk/*
%dir /opt/lsb/doc/%{name}
/opt/lsb/doc/%{name}/*
