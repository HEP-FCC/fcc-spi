#!/usr/bin/env python

import os
import sys
import re
import argparse
import subprocess
import shutil
import requests
import buildinfo2json

# gcc path

GCCPATHS = {'AFS': '/afs/cern.ch/sw/lcg/contrib/gcc', 'CVMFS': '/cvmfs/sft.cern.ch/lcg/contrib/gcc/', 'EOS': '/cvmfs/sft.cern.ch/lcg/contrib/gcc/'}
RELEASEPATHS = {'AFS': '/afs/cern.ch/sw/lcg/releases', 'CVMFS': '/cvmfs/sft.cern.ch/lcg/releases', 'EOS': '/cvmfs/sft.cern.ch/lcg/releases'}

def getCompilerPath(version, platform, fstype=None):
  global GCCPATHS
  if fstype is None:
    for t in ('AFS', 'CVMFS', 'EOS'):
      if os.path.exists(GCCPATHS[t]):
        fstype = t
        break
  if fstype in GCCPATHS:
    path = GCCPATHS[fstype]
  else:
    raise RuntimeError("Wrong fs type '{0}'".format(fstype))
  if os.path.exists(os.path.join(path, version)):
    path = os.path.join(path, version)
  elif os.path.exists(os.path.join(os.path.join(path, '.'.join(version.split('.')[:-1])))):
    path = os.path.join(os.path.join(path, '.'.join(version.split('.')[:-1])))
  if os.path.exists(os.path.join(path, platform)):
    return os.path.join(os.path.join(path, platform))
  else:
    raise RuntimeError("Cannot find compiler in {0}".format(os.path.join(path, platform)))


def checkURL(url):
  if "file://" in url:
    return True if os.system('stat {0} 1>/dev/null 2>/dev/null'.format(url.replace('file://', ''))) == 0 else False
  ret = requests.head(url)
  return ret.status_code == 200


class Package:
  cache = {}

  def __init__(self, name, version, hashstr, directory, dependencies, platform, compiler):
    self.name = name
    self.version = version
    self.hashstr = hashstr
    self.directory = directory
    self.dependencies = dependencies
    self.platform = platform
    self.compiler = compiler

  def getName(self):
    return "{0}-{1}".format(self.name, self.version)

  def getPackageFilename(self):
    return "{0}-{1}_{2}-{3}.tgz".format(self.name, self.version, self.hashstr, self.platform)

  def getModifiedInstallPath(self):
    return os.path.join(self.directory, "{0}-{1}".format(self.version, self.hashstr), self.platform)

  def getInstallPath(self):
    return os.path.join(self.directory, self.version, self.platform)

class InstallProcess:
  def __init__(self, releaseurl, description, prefix='.', lcgversion='auto',  updatelinks=False, nocheck=False, nightly=False, limited=False, endsystem='cvmfs'):
    self.packages = []
    self.releaseurl = releaseurl
    self.prefix = prefix
    #self.endsystem = endsystem
    if "afs" in endsystem:
      self.basepath = RELEASEPATHS['AFS']
    elif "eos" in endsystem:
      self.basepath = RELEASEPATHS['EOS']
    else:
      self.basepath = RELEASEPATHS['CVMFS']

    if lcgversion != "auto":
      self.lcgversion = lcgversion
    else:
      lcgversion = description.split("_")[1]
    self.description = description
    self.platform = self.getPlatform(description)
    self.nakedplatform = self.getNakedPlatform(self.platform)
    self.nightly = nightly
    self.updatelinks = updatelinks
    self.limited = limited
    print "Starting " + self.getType()
    if description != "":
      self.fillPackages(description)
      if not nocheck:
        print "Checking all tgz files ..."
        self.checkAll()

  #Hook methods. Concrete details may differ in each subclass
  def getLinkpath(self):
      raise NotImplementedError()
  def getDatapath(self):
      raise NotImplementedError()
  def getPostinstallFile(self):
      raise NotImplementedError()
  def getType(self):
      raise NotImplementedError()

  @staticmethod
  def getPlatform(description):
    return '_'.join(description.replace('.txt', '').split('_')[2:])

  @staticmethod
  def getNakedPlatform(platform):
    arch, osvers, compvers, buildtype = platform.split('-')
    return '-'.join([arch.split('+')[0], osvers, compvers, buildtype])

  def fillPackages(self, description):
    text = self.getDescContent(os.path.join(self.releaseurl, self.description))
    lines = text.split('\n')
    # limited contains a line with PKGS_OK
    self.limited = 'PKGS_OK' in lines[0]

    if self.limited:
      selectedpackages = lines[0].split('PKGS_OK ')[1].split(' ')

    for line in lines:
      if line[0] == '#' : continue
      d = buildinfo2json.parse(line)

#     special platform with instruction set
      if 'ISET' not in d : platform = self.nakedplatform
      else :               platform = self.platform

#      if "rootext" in self.lcgversion:
      if self.limited:
        for i in selectedpackages:
          if i != d['NAME']:
            continue
          else:
            if d['NAME'] != d['DESTINATION']:
              print "# Skip package", d['NAME'], 'as it should be packaged in', d['DESTINATION']
              continue
            p = Package(d['NAME'], d['VERSION'], d['HASH'], d['DIRECTORY'], d['DEPENDS'], platform, d['COMPILER'])
            self.packages.append(p)
      else:
        if d['NAME'] != d['DESTINATION']:
        # bundled package
          print "# Skip package", d['NAME'], 'as it should be packaged in', d['DESTINATION']
          continue
        p = Package(d['NAME'], d['VERSION'], d['HASH'], d['DIRECTORY'], d['DEPENDS'], platform, d['COMPILER'])
        self.packages.append(p)

  @staticmethod
  def getDescContent(url):
    url = str(url)
    if not checkURL(url):
      raise RuntimeError("URL {0} not found.".format(url))
    p = subprocess.Popen(['curl', '-s', url], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = p.communicate()
    if p.returncode == 0:
      return stdout.strip()
    else:
      print "ERROR:"
      print stderr.strip()
      raise RuntimeError("Cannot get info from " + url)

  def getListOfReleases(self):
    url = self.releaseurl
    if not checkURL(url):
      raise RuntimeError("URL {0} not found.".format(url))
    if 'file://' in url:
      p = subprocess.Popen(['find', url.replace('file://', ''), '-type', 'f', '-name', 'LCG_*.txt'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    else:
      p = subprocess.Popen(['curl', '-s', url], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = p.communicate()
    if p.returncode == 0:
      if "file://" in url:
        a = stdout.strip().split('\n')
      else:
        a = re.findall('.*href="?(.+.txt)"?>.*', stdout)
      return [os.path.basename(x) for x in a]
    else:
      print "ERROR:"
      print stderr.strip()
      raise RuntimeError("Cannot get info from " + url)

  def postinstall(self, postfile):
    p = subprocess.Popen(['env', 'INSTALLDIR={0}'.format(self.prefix), 'bash', postfile], stdout=subprocess.PIPE,
      stderr=subprocess.PIPE)
    stdout, stderr = p.communicate()
    if p.returncode == 0:
      print "  OK."
      return True
    else:
      print "  ERROR:"
      print stderr.strip()
      raise RuntimeError("Error in post-install step")

  @staticmethod
  def createLinks(frompath, topath, relative=True, updatelinks=False):
    # Destroy current link to create a new one to the new installed package
    # Maintain old pointed package
    if updatelinks and os.path.exists(topath):
        print "  Removing existing link {0}->{1}".format(topath, os.path.realpath(topath))
        os.unlink(topath)

    if frompath[-1] == '/':
      frompath = frompath[:-1]
    if topath[-1] == '/':
      topath = topath[:-1]
    try:
      print "  Checking that symbolic link {0} exists".format(topath)
      if not os.path.exists(topath):
        if not os.path.exists(os.path.dirname(topath)):
          os.makedirs(os.path.dirname(topath))
        if relative:
          frompath = os.path.relpath(frompath, topath)
          frompath = '/'.join(frompath.split('/')[1:])
        print "  Create symbolic link {0}->{1}".format(topath, frompath)
        os.symlink(frompath, topath)
      else:
        print "  Existing link: {0}->{1}".format(topath, os.path.realpath(topath))
      return True
    except Exception as e:
      raise RuntimeError("Error during managing symlinks: " + str(e))

  # Template method
  def install(self, package, opts='-xpz', force=False):

    # Get source and destination paths for links
    linkpath = self.getLinkpath(package)
    datapath = self.getDatapath(package)

    unTARdone = False
    # Manage copy of file or creation of links
    if not self.isInstalled(package) or force :
      print "  Extract archive from", os.path.join(self.releaseurl, package.getPackageFilename())
      rc = self.unTAR(package, opts)
      unTARdone = True
      postinstallfile = self.getPostinstallFile(package)

      if os.path.exists(postinstallfile):
        print "  Launch .post-install.sh"
        rc = rc and self.postinstall(postinstallfile)
    else:
        rc = True

    # Release installation always creates link from .../release/LCG/pkg -> .../release/pkg
    if (self.nightly and not unTARdone) or (not self.nightly):
        if(os.path.exists(datapath)):
           rc = rc and self.createLinks(datapath, linkpath, updatelinks=self.updatelinks)
        else:
           if self.limited :
              # Ignoring the prackage....
              rc = True
           else :
              raise RuntimeError("Path not exists: " + datapath)
    # else:
    #   rc = True
    #   # Check if datapath exists, to avoid link to an empty path
    #   if(os.path.exists(datapath)):
    #       rc = rc and self.createLinks(datapath, linkpath)
    #   else:
    #       raise RuntimeError("Path not exists: " + datapath)
    ## TODO Check this part -> Otherwise there is no link from /release/LCG-Version/pkg to /release/pkg-hash
    ## when a package is not previously install or force is eneabled
    return rc

  def checkAll(self):
    for package in self.packages:
      filename = os.path.join(self.releaseurl, package.getPackageFilename())
      if not checkURL(filename):
#        if self.nightly  or "rootext" in self.lcgversion:
        if self.nightly  or self.limited:
          print "This package does not exist in this configuration, however we continue: ", filename
        else :
          raise RuntimeError("URL not found: " + filename)
    return True

  def unTAR(self, package, opts='-xpz'):
    if self.nightly :
      opts += " -v "
    else :
      opts += " -v --show-transformed-names --transform 's,/{0}/{2},/{0}-{1}/{2},g'".format(package.version, package.hashstr, package.platform)  # verbose (to keep list of untared files)
    filename = os.path.join(self.releaseurl, package.getPackageFilename())
    p = subprocess.Popen('curl -s {0} | tar {1} -C {2} -f -'.format(filename, opts, self.prefix),
      stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    stdout, stderr = p.communicate()

    # Remove only case not matched by the previous regex expresion (packageName/version-withoutHash)
    unmatched = os.path.join(self.prefix, package.directory, package.version)
    if os.path.exists(unmatched):
        # Check whether it is empty
        otherdirs = os.listdir(unmatched)
        if not otherdirs:
            os.rmdir(unmatched)
        elif otherdirs == ["share"]:
            shutil.rmtree(unmatched)

    if p.returncode == 0:
      print "  File:", filename, "Extracted:", len(stdout.strip().split('\n')), 'files'
      return True
    else:
      print "  ERROR: cannot properly run the following command:"
      print '  curl -s', filename, ' | tar', opts, '-C', self.prefix, '-f', '-'
      print stderr
      if len(stdout.strip()) != 0:
        tarprefix = sorted(stdout.strip().split('\n'))[0]
        tarprefix = os.path.join(self.prefix, tarprefix)
        print "  Try to revert changes: rm -rf {0}".format(tarprefix)
        try:
          if tarprefix != "":
            shutil.rmtree(tarprefix)
          print "  FAILED. But installation directory should be clean."
        except:
          print "  ERROR: cannot remove " + tarprefix
        raise RuntimeError(stderr)
      else:
#        if self.nightly  or "rootext" in self.lcgversion:
        if self.nightly or self.limited:
          print "Nothing has been extracted. Probably file not found. anyway let's move on"
        else :
          raise RuntimeError("Error during extraction.")

  def isInstalled(self, package):
    if self.nightly :
      installpath = os.path.join(self.basepath, package.getModifiedInstallPath())
    else :
      installpath = os.path.join(self.prefix, package.getModifiedInstallPath())
    print "  Checking that {0} exists".format(installpath)
    return os.path.exists(installpath)

  def getPackages(self):
    return self.packages

# Specific installation details for Nighties
class InstallNightlyProcess(InstallProcess):
  def getLinkpath(self,package):
      return self.prefix + "/" + package.getInstallPath()
  def getDatapath(self,package):
      return os.path.join(self.basepath, package.getModifiedInstallPath())
  def getPostinstallFile(self,package):
      prefixinstallpath = os.path.join(self.prefix,package.getInstallPath())
      return os.path.join(prefixinstallpath, '.post-install.sh')
  def getType(self):
      return "Nightly Installation"

# Specific installation type for normal Release (install all packages without links)
class InstallReleaseProcess(InstallProcess):
  def getLinkpath(self,package):
      return os.path.join(self.prefix, str(self.lcgversion), package.getInstallPath())
  def getDatapath(self,package):
      return os.path.join(self.prefix, package.getModifiedInstallPath())
  def getPostinstallFile(self,package):
      return os.path.join(self.getDatapath(package), '.post-install.sh')
  def getType(self):
      return "Release Installation"

# Specific installation details for Nighties
class InstallLimitedProcess(InstallReleaseProcess):
  def getType(self):
      return "Limited Installation"

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('-d', '--description', help="Description name", default='', dest='description')
  parser.add_argument('-p', '--prefix', help="Installation prefix", default='.', dest='prefix')
  parser.add_argument('-u', '--release-url', help="URL of release area (use file:// for local targets)",
    default='http://lcgpackages.cern.ch/tarFiles/releases', dest='releaseurl')
  parser.add_argument('-r', '--release-number', help="Release number", default='auto', dest='releasever')
  parser.add_argument('-f', '--force-install', help="Force untar selected packages", default=[], dest='force',
    nargs='*')
  parser.add_argument('-n', '--dry-run', help="Be pacific, don't do anything", default=False, action='store_true',
    dest='dryrun')
  parser.add_argument('-l', '--list', help="Just list packages", default=False, action='store_true', dest='justlist')
  parser.add_argument('-y', '--nightly', help="Install as nightly", default=False, action='store_true', dest='nightly')
  parser.add_argument('-e', '--endsystem', help="installation in CVMFS, EOS or AFS", default='CVMFS', dest='endsystem')
  parser.add_argument('--update', help="Force to update existing links", default=False, action='store_true', dest='updatelinks')
  parser.add_argument('-o', '--other', help="Installation of limited amount of packages, to be used by rootext or geantv", default=False, action='store_true', dest='limited')

  args = parser.parse_args()

  args.prefix = os.path.abspath(args.prefix)
  # def __init__(self, releaseurl = 'http://lcgpackages.cern.ch/tarFiles/releases', description, prefix = '.', lcgversion = 'test'):

  # Check the installation type to execute
  installType = None
#  if "rootext" in args.releasever:
  if args.limited:
      installType = InstallLimitedProcess
  elif args.nightly:
      installType = InstallNightlyProcess
  else:
      installType = InstallReleaseProcess

  installation = installType(args.releaseurl,
                             args.description,
                             args.prefix,
                             args.releasever,
                             updatelinks=args.updatelinks,
                             nocheck=args.justlist,
                             nightly=args.nightly,
                             limited=args.limited,
                             endsystem=args.endsystem)

  if args.description == '':
    print "List of available releases in {0}:".format(args.releaseurl)
    print "\n".join(installation.getListOfReleases())
    sys.exit(0)

  if args.justlist:
    print "Packages:"
    print "\n".join([x.getName() for x in installation.getPackages()])
    sys.exit(0)

  idx = 1
  for package in installation.getPackages():
    if not args.dryrun:
      print "[{0:03d} / {1:03d}] Start installation process for ".format(idx,
        len(installation.getPackages())), package.getName()
      force = package.getName() in args.force
      if force:
        print "  Force reinstalling has been requested"
      installation.install(package, force=force)
      print "Finished."
    else:
      print "Installing", package.getName(), ": DRY RUN"
    idx += 1
  # gcc installation
  compiler = set([x.compiler for x in installation.packages])
  if len(compiler) == 0:
    raise RuntimeError("No compiler found in release")
  elif len(compiler) > 1:
    print "WARNING: More than one compilers found in release:", compiler
  compiler = list(compiler)[0]
  compilerplatform = list(set([x.platform for x in installation.packages]))[0]
  compilerplatform = '-'.join(compilerplatform.split('-')[:-2])
  # remove architecture part (avx,avx2,fma..)
  compilerplatform = re.sub('\+.*-', '-', compilerplatform)
  compilerversion = compiler.split()[1].strip()
  if args.prefix.startswith('/afs/'):
    fstype = 'AFS'
  elif args.prefix.startswith('/cvmfs/'):
    fstype = 'CVMFS'
  elif args.prefix.startswith('/eos/'):
    fstype = 'EOS'
  else:
    fstype = None
  if "ubuntu" not in args.description and "clang" not in args.description:
    compilerpath = getCompilerPath(compilerversion, compilerplatform, fstype)
    if not os.path.exists(os.path.join(args.prefix, 'gcc', compilerversion, compilerplatform)):
      installation.createLinks(compilerpath, os.path.join(args.prefix, 'gcc', compilerversion, compilerplatform), False)
      if not os.path.exists(os.path.join(args.prefix, 'LCG_' + str(args.releasever), 'gcc', compilerversion, compilerplatform)):
        installation.createLinks(compilerpath,
                                 os.path.join(args.prefix, "LCG_" + str(args.releasever), 'gcc', compilerversion, compilerplatform), False)


if __name__ == "__main__":
  main()
