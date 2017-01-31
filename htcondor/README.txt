The HTCondor config.d on the osg-flock host contains files from a set
of RPMs, as well as our custom config. In order for us to separate
the files, any files under config.d/ in this git repositor has to be
named with a keyword: *_osgflockgit.config

Changes are automatically applied to the osg-flock host.

