Name:      osg-flock
Version:   1.6
Release:   3%{?dist}
Summary:   OSG configurations for a flocking host

License:   Apache 2.0
URL:       https://opensciencegrid.org/docs/submit/osg-flock

BuildArch: noarch

Requires(post): gratia-probe-condor-ap
Requires: condor

Source0: %{name}-%{version}%{?gitrev:-%{gitrev}}.tar.gz

%description
%{summary}

%prep
%setup -q

%build

%install
rm -fr $RPM_BUILD_ROOT

# Install condor configuration
install -d $RPM_BUILD_ROOT/%{_sysconfdir}/condor/config.d
install -m 644 rpm/80-osg-flocking.conf $RPM_BUILD_ROOT/%{_sysconfdir}/condor/config.d


# Install gratia configuration
install -d $RPM_BUILD_ROOT/%{_sysconfdir}/gratia/condor/

%post
# Set OSPool specific Gratia probe config
probeconfig=/etc/gratia/condor-ap/ProbeConfig
overrides=(
    'SuppressGridLocalRecords="1"'
    'MapUnknownToGroup="1"'
    'MapGroupToRole="1"'
    'VOOverride="OSG"'
)

for override in "${overrides[@]}"; do
    key=${override%%=*}
    if grep "$override" $probeconfig 2>&1 > /dev/null; then
        # override already present
        continue
    elif grep "$key" $probeconfig 2>&1 > /dev/null; then
        # config value already exists but is not overriden
        sed -i -e "s/$key.*/$override/" $probeconfig
    else
        # config value doesn't exist
        sed -i -e "s/\(EnableProbe.*\)/\1\n    $override/" $probeconfig
    fi
done

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)

%config(noreplace) %{_sysconfdir}/condor/config.d/80-osg-flocking.conf


%changelog
* Thu Nov 4 2021 Brian Lin <blin@cs.wisc.edu> - 1.6-3
- Append OSPool specific ProbeConfig changes in post-installation
  (SOFTWARE-4846)

* Wed Oct 27 2021 Brian Lin <blin@cs.wisc.edu> 1.6-2
- Remove reference to old ProbeConfig

* Mon Oct 25 2021 Mats Rynge <rynge@isi.edu> 1.6-1
- Now requires gratia-probe-condor-ap, probe config has been removed

* Fri Oct 1 2021 Mats Rynge <rynge@isi.edu> 1.5-1
- Moved to new HTCondor Cron Gratia setup

* Wed Sep 29 2021 Mats Rynge <rynge@isi.edu> 1.4-1
- Updating for OSG 3.6, idtoken auth

* Fri Jan 1 2021 Mats Rynge <rynge@isi.edu> 1.3-1
- Enable Schedd AuditLog by default in osg-flock (SOFTWARE-4390)

* Fri Oct 23 2020 Brian Lin <blin@cs.wisc.edu> 1.2-2
- Fix paths to configuration source files

* Thu Oct 22 2020 Mats Rynge <rynge@isi.edu> 1.2-1
- Moved to IDTOKENS on HTCondor versions greater than 8.9.6

* Wed Jun 8 2020 Brian Lin <blin@cs.wisc.edu> 1.1-2
- Fix CA requirements to work with osg-ca-scripts or certificate bundles

* Mon Apr 10 2019 Brian Lin <blin@cs.wisc.edu> 1.1-1
- Add new OSG flock host certificate DN (SOFTWARE-3603)

* Fri Sep 07 2018 Suchandra Thapa <ssthapa@uchicago.edu> 1.0-1
- Initial meta package based in part on osg-condor-flock rpms

