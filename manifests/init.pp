# == Class: apache
#
# This class configures an Apache server.  It ensures that the appropriate
# files are in the appropriate places and can optionally rsync the
# /var/www/html content.
#
# Ideally, we will move over to the Puppet Labs apache module in the future but
# it's going to be quite a bit of work to port all of our code.
#
# == Parameters
#
# NOTE: If a parameter is not listed here then it is part of the
# standard Apache configuration set and the stock Apache documentation
# should be referenced.
#
# [*data_dir*]
#   Type: Absolute Path
#   Default: versioncmp(simp_version(),'5') ? { '-1' => '/srv/www', default => '/var/www' }
#
#   The location where apache web data should be stored. Set to /srv/www for
#   legacy reasons.
#
# [*rsync_web_root*]
#   Type: Boolean
#   Whether or not to rsync over the web root.
#
# [*ssl*]
#   Type: on|off
#   Whether or not to enable SSL. You will need to set the Hiera
#   variables for apache::ssl appropriately for your needs.
#
# == Authors
#
# * Trevor Vaughan <tvaughan@onyxpoint.com>
#
class apache (
  $data_dir = versioncmp(simp_version(),'5') ? { '-1' => '/srv/www', default => '/var/www' },
  $rsync_server = hiera('rsync::server'),
  $rsync_timeout = hiera('rsync::timeout','2'),
  $rsync_web_root = true,
  $ssl = true
) {
  validate_absolute_path($data_dir)
  validate_bool($ssl)
  validate_string($rsync_server)
  validate_integer($rsync_timeout)
  validate_bool($rsync_web_root)

  include '::apache::install'
  include '::apache::conf'

  if $ssl {
    include '::apache::ssl'
    Class['::apache::install'] -> Class['::apache::ssl']
  }

  Class['::apache::install'] -> Class['::apache']
  Class['::apache::install'] -> Class['::apache::conf']
  Class['::apache::install'] ~> Service['httpd']

  if $::operatingsystem in ['RedHat','CentOS'] {
    if (versioncmp($::operatingsystemmajrelease,'7') >= 0) {
      $apache_homedir = '/usr/share/httpd'
    }
    else {
      $apache_homedir = '/var/www'
    }
  }
  else {
    $apache_homedir = '/var/www'
  }


  $_modules_target = $::hardwaremodel ? {
    'x86_64' => '/usr/lib64/httpd/modules',
    default  => '/usr/lib/httpd/modules'
  }

  file { $data_dir:
    ensure => 'directory',
    owner  => 'root',
    group  => 'apache',
    mode   => '0640'
  }

  file { '/etc/httpd/conf/magic':
    owner  => 'root',
    group  => 'apache',
    mode   => '0640',
    source => 'puppet:///modules/apache/magic',
    notify => Service['httpd'],
  }

  file { '/etc/httpd/conf.d/welcome.conf': ensure => 'absent' }

  file { '/etc/mime.types':
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    notify => Service['httpd'],
  }

  file { '/etc/httpd/logs':
    ensure => 'symlink',
    target => '/var/log/httpd',
    force  => true
  }

  file { '/etc/httpd/modules':
    ensure => 'symlink',
    target =>  $_modules_target,
    force  => true
  }

  file { '/etc/httpd/run':
    ensure => 'symlink',
    target => '/var/run/httpd',
    force  => true,
  }

  file { '/var/log/httpd':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0700'
  }

  file { 'httpd_modules':
    ensure => 'directory',
    path   => $_modules_target,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    notify => Service['httpd']
  }

  group { 'apache':
      ensure    => 'present',
      allowdupe => false,
      gid       => '48'
  }

  if $rsync_web_root {
    include '::rsync'

    # Rsync the /var/www space from the rsync server.
    # Add anything here you want to go to every web server.
    rsync { 'site':
      user     => 'apache_rsync',
      password => passgen('apache_rsync'),
      source   => 'apache/www',
      target   => '/var',
      server   => $rsync_server,
      timeout  => $rsync_timeout,
      delete   => false
    }
  }

  if $::selinux_current_mode and $::selinux_current_mode != 'disabled' {
    selboolean { [
      'httpd_verify_dns',
      'allow_ypbind',
      'allow_httpd_mod_auth_pam',
      'httpd_can_network_connect'
    ]:
      persistent => true,
      value      => 'on'
    }
  }

  service { 'httpd':
    ensure     => 'running',
    enable     => true,
    hasrestart => false,
    hasstatus  => true,
    # The sleep 3 is in place to prevent a race condition from happening and
    # the reload || restart is in place to try to force a clean restart if a
    # reload fails to do the job.
    restart    => '/bin/sleep 3; /sbin/service httpd reload || /sbin/service httpd restart',
    require    => File['/etc/httpd/conf/httpd.conf']
  }

  user { 'apache':
    ensure     => 'present',
    allowdupe  => false,
    gid        => '48',
    home       => $apache_homedir,
    membership => 'minimum',
    shell      => '/sbin/nologin',
    uid        => '48',
    require    => Group['apache']
  }
}
