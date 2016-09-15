# %{ver}, %{rel}, %{eyapp_ver} are provided by the Makefile
%define ver @VERSION@
%define rel @RELEASE@
%define eyapp_ver @EYAPP_VER@
%define basedir /opt/lsb

Summary: LSB Shell Script Application Checker
Name: lsb-appchk-shell
Version: %{ver}
Release: %{rel}
License: GPL
Group: Development/Tools
Source: %{name}-%{version}.tar.gz
Source1: http://search.cpan.org/CPAN/authors/id/C/CA/CASIANO/Parse-Eyapp-%{eyapp_ver}.tar.gz
URL: http://www.linuxbase.org/test
BuildRoot: %{_tmppath}/%{name}-root
AutoReqProv: no
BuildArch: noarch
BuildRequires: perl 

%description
This is the official package version of the LSB Shell Script Checker. 

#==================================================
%prep
%setup -q -a1

#==================================================
%build
# build/install Parse-Eyapp first
cd Parse-Eyapp-%{eyapp_ver}
perl Makefile.PL PREFIX=../perl-local
make
make install
cd ..
# now the checker
#export PERL5LIB=perl-local/lib/perl5/site_perl/
# now generating to different place, may have to add some
# logic to try to detect the location
export PERL5LIB=./perl-local/share/perl5
# for some reason, some perl installs put the binary in "local"
if [ -d "./perl-local/local" ];then
  export PATH=$PATH:$(pwd)/perl-local/local/bin
else
  export PATH=$PATH:$(pwd)/perl-local/bin
fi

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
