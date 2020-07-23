#!/usr/bin/env python
import os, sys, shutil, glob

# name-hash; package name; version; hash; full directory name; comma separated dependencies
#  COMPILER: GNU 4.8.1, HOSTNAME: lcgapp07.cern.ch, HASH: 9ccc5, DESTINATION: CASTOR, NAME: CASTOR, VERSION: 2.1.13-6,

class PackageInfo(object):

   def __init__(self,name,destination,hash,version,directory,dependencies):
     self.name = name
     self.destination = destination
     self.hash = hash
     self.version = version
     self.directory = directory
     self.dependencies = dependencies
     if name == destination:
        self.is_subpackage = False
     else:
        self.is_subpackage = True
   def compile_summary(self):
     #create dependency string
     if self.is_subpackage:
        return ""
     dependency_string = ",".join(self.dependencies)
     return "%s; %s; %s; %s; %s" %(self.name, self.hash, self.version, self.directory, dependency_string)

def fake_meta_package(name, packages, lcg_version, platform):
    oldfile = open("/afs/cern.ch/sw/lcg/releases/LCG_%s/LCG_externals_%s.txt" %(lcg_version,platform), "r")
    for line in oldfile.readlines():
      if line.startswith(name):
        pkg_hash = line.split(";")[1].strip()
        pkg_version = line.split(";")[2].strip()
        pkg_directory = line.split(";")[3].strip()
        pkg_dependencies = set( (line.split(";")[4].strip()).split(",") )

        return PackageInfo(name,name,pkg_hash,pkg_version,pkg_directory, pkg_dependencies)

def get_fields(package):
   fields = {}
   deps = False
   oldformat = not 'DEPENDS' in package
   for e in package.split(','):
      if not e.strip() : continue
      if not deps:
         k,v = map(str.strip, (e.split(':')[0], ':'.join(e.split(':')[1:])))
         if k == 'DEPENDS' :
            fields[k] = v and [v] or []
            deps = True
         elif oldformat and k == 'VERSION':
            fields[k] = v
            fields['DEPENDS'] = []
            deps = True
         else:
            fields[k] = v
      else:
         if e.strip() :
            fields['DEPENDS'].append(e.strip())
   return fields

def create_package_from_file(directory, filename, packages):
   content = open(filename).read()
   keys = get_fields(content)
   compiler_version = keys['COMPILER'].split()[1]
   name = keys['NAME']
   destination = keys['DESTINATION']
   hash = keys['HASH']
   version = keys['VERSION']

   # handle duplicate entries (like herwig++/herwigpp)
   # only take the "++" case
   if packages.has_key(name+hash):
     old_package = packages[name+hash]
     if old_package.version == version:
       if old_package.directory < directory:
         return

   # now handle the dependencies properly
   dependency_list = keys['DEPENDS']
   dependencies = set()
   for dependency in dependency_list:
       l = dependency.rsplit("-",5)
       ll = l[0]+"-"+l[-1]
       dependencies.add(ll)
   # TODO: hardcoded meta-packages
   if name in ["pytools","pyanalysis","pygraphics"]:
     dependencies = set()
   if name == "ROOT":
     dependencies.discard("pythia8")
   #ignore hepmc3
   if name == "hepmc3":
      pass
   else:
     if "MCGenerators" in directory:
       packages[name+hash] = PackageInfo(name,destination,hash,version,directory,dependencies)
     else:
       packages[name] = PackageInfo(name,destination,hash,version,directory,dependencies)
   return compiler_version

#########################
if __name__ == "__main__":

  options = sys.argv
  if len(options) != 5:
    print "Please provide DIR, PLATFORM, FCCSW_version and whether it is RELEASE or UPGRADE as command line parameters"
    sys.exit()
  name, thedir, platform, version, mode = options
  compiler = "".join([s for s in platform.split("-")[2] if not s.isdigit()])
  compiler_version = ""
  packages = {}
  # collect all .buildinfo_<name>.txt files
  files = glob.glob(os.path.join(thedir, '*/*', platform,'.buildinfo_*.txt'))
  files.extend(glob.glob(os.path.join(thedir, 'MCGenerators/*/*', platform,'.buildinfo_*.txt')))
#  files.extend(glob.glob(os.path.join(thedir, 'Grid/*/*', platform,'.buildinfo_*.txt')))
  for afile in files:
      path , fname = os.path.split(afile)
      tmp_compiler_version = create_package_from_file(os.path.split(afile)[0], afile, packages)
      if tmp_compiler_version > compiler_version:
           compiler_version = tmp_compiler_version

  # now compile entire dependency lists
  # every dependency of a subpackage is forwarded to the real package

  # sometimes not an entire meta-package is built
  # so we need to create fake packages to replace them
  # these are used during dependency resolution, but deleteded before the summary is written out
  fakepackages = {}
  for name,package in packages.iteritems():
     if package.is_subpackage == True:
        # check whether the meta-package was actually fully built
        # if not, insert a temporary fake package
        if packages.has_key(package.destination):
          packages[package.destination].dependencies.update(package.dependencies)
        else:
          fakepackages[package.destination] = fake_meta_package(package.destination, packages, version, platform)
  packages.update(fakepackages)

  # now remove all subpackages in dependencies and replace them by real packages
  for name, package in packages.iteritems():
    if package.is_subpackage == False:
      toremove = set()
      toadd = set()
      for dep in package.dependencies:
        depname = dep.split("-")[0]
        if packages.has_key(depname):
          if packages[depname].is_subpackage:
            toremove.add(dep)
            destination = packages[depname].destination
            toadd.add("%s-%s"%(destination,packages[destination].hash))
      for dep in toremove:
         package.dependencies.remove(dep)
      for dep in toadd:
         package.dependencies.add(dep)

    # make sure that a meta-package doesn't depend on itself
    package.dependencies.discard(name)

  # now remove the fake packages again...
  for fake in fakepackages.iterkeys():
    del packages[fake]

  # write out the files to disk
  # first the externals
  thefile = open(thedir+"/fccsw_%s.txt" %platform, "w")
  thefile.write( "PLATFORM: %s\nVERSION: %s\nCOMPILER: %s;%s\n" %(platform, version, compiler, compiler_version) )
  for name,package in packages.iteritems():
      result = package.compile_summary()
      if result != "" and "MCGenerators" not in result: #TODO: HACK
        thefile.write(result+"\n")
  thefile.close()
  # then the generators
  thefile = open(thedir+"/fccsw_generators_%s.txt" %platform, "w")
  thefile.write( "PLATFORM: %s\nVERSION: %s\nCOMPILER: %s;%s\n" %(platform, version, compiler, compiler_version) )
  for name,package in packages.iteritems():
     result = package.compile_summary()
     if result != "" and "MCGenerators" in result: #TODO: HACK

       thefile.write(result+"\n")
  thefile.close()

  # and in case of adding generators afterwards we want to have a merged file as well
  if mode == "UPGRADE":
    oldfile = open("/afs/cern.ch/sw/lcg/releases/LCG_%s/LCG_generators_%s.txt" %(version,platform), "r")
    thefile = open(thedir+"/fccsw_%s.txt" %platform, "w")
    for line in oldfile.readlines():
      thefile.write(line)
    for name,package in packages.iteritems():
       result = package.compile_summary()
       if result != "" and "MCGenerators" in result: #TODO: HACK
         thefile.write(result+"\n")
    thefile.close()
    oldfile = open("/afs/cern.ch/sw/lcg/releases/LCG_%s/LCG_externals_%s.txt" %(version,platform), "r")
    thefile = open(thedir+"/fccsw_%s.txt" %platform, "w")
    for line in oldfile.readlines():
      thefile.write(line)
    for name,package in packages.iteritems():
       result = package.compile_summary()
       if result != "" and "MCGenerators" not in result: #TODO: HACK
         thefile.write(result+"\n")
    thefile.close()


  # add the contrib file to 'thedir'
  shutil.copyfile("/cvmfs/fcc.cern.ch/sw/releases/fccsw_contrib_%s.txt" %platform,"%s/fccsw_contrib_%s.txt"%(thedir,platform))
