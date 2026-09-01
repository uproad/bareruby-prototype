# frozen_string_literal: true

# This checkout is a project of its own gems.
#
# It is here for one reason: a Gemfile is what says where a project's root is, and
# everything a run reaches for that it did not bring with it — config/target.yml, the
# source compiled when none is named, build/ and dump/ — is found from that root. A
# checkout that ran its own commands without one would be the single case that had to
# find its root some other way, which is exactly the second answer this design exists to
# avoid.
#
# ./bareruby reads the two gems this repository *is* straight from the working tree, so
# nothing here has to be installed for it to run. Installing it is the other way to work,
# and the one a user's project takes.
source "https://rubygems.org"

path "gems" do
  gem "bareruby_prot"
  gem "bareruby_prot-binding-arduino"
  gem "bareruby_prot-binding-esp_idf"
  gem "bareruby_prot-binding-pico_sdk"
  gem "bareruby_prot-binding-stm32cube"
  gem "bareruby_prot-simulator"
  gem "bareruby_prot-stdlib-adc"
  gem "bareruby_prot-stdlib-gpio"
  gem "bareruby_prot-stdlib-i2c"
  gem "bareruby_prot-stdlib-onboard_led"
  gem "bareruby_prot-stdlib-pwm"
  gem "bareruby_prot-stdlib-uart"
end
