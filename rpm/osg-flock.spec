Name:      osg-flock
Version:   1.1
Release:   2%{?dist}
Summary:   OSG configurations for a flocking host

License:   Apache 2.0
URL:       https://support.opensciencegrid.org/support/solutions/articles/12000030368-submit-node-flocking-to-osg#gratia-probe-configuration

BuildArch: noarch

Requires: grid-certificates >= 7
Requires: gratia-probe-glideinwms
Requires: fetch-crl
Requires: condor

Source0: 80-osg-flocking.conf
Source1: ProbeConfig

%description
%{summary}

%prep

%build

%install
rm -fr $RPM_BUILD_ROOT

# Install condor configuration
install -d $RPM_BUILD_ROOT/%{_sysconfdir}/condor/config.d
install -m 644 %{SOURCE0} $RPM_BUILD_ROOT/%{_sysconfdir}/condor/config.d


# Install gratia configuration
install -d $RPM_BUILD_ROOT/%{_sysconfdir}/gratia/condor/
install -m 644 %{SOURCE1} $RPM_BUILD_ROOT/%{_sysconfdir}/gratia/condor/ProbeConfig-flocking

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)

%config(noreplace) %{_sysconfdir}/condor/config.d/80-osg-flocking.conf
%config(noreplace) %{_sysconfdir}/gratia/condor/ProbeConfig-flocking


%changelog
* Wed Jun 8 2020 Brian Lin <blin@cs.wisc.edu> 1.1-2
- Fix CA requirements to work with osg-ca-scripts or certificate bundles

* Wed Apr 10 2019 Brian Lin <blin@cs.wisc.edu> 1.1-1
- Add new OSG flock host certificate DN (SOFTWARE-3603)

* Fri Sep 07 2018 Suchandra Thapa <ssthapa@uchicago.edu> 1.0-1
- Initial meta package based in part on osg-condor-flock rpms

