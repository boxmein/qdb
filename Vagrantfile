# -*- mode: ruby -*-
# vi: set ft=ruby :

VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "ubuntu/trusty64"
  config.vm.provision :shell, :path => "vagrant-bootstrap.sh"
  # When user runs `ruby qdb.rb` or `bundle exec rackup config.ru`
  config.vm.network "forwarded_port", :guest => 4567, :host => 3001
  # When user runs `foreman start web`
  config.vm.network "forwarded_port", :guest => 5000, :host => 3002
end
