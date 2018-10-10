use Mix.Releases.Config,
  default_release: :default,
  default_environment: :prod

environment :prod do
  set(include_erts: true)
  set(include_src: false)
  set(pre_configure_hook: "rel/hooks/pre_configure")
end

release :bob do
  set(version: current_version(:bob))
  set(cookie: "")
  set(vm_args: "rel/vm.args")
end
