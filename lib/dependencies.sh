measure_size() {
  echo "$((du -s node_modules 2>/dev/null || echo 0) | awk '{print $1}')"
}

list_dependencies() {
  local build_dir="$1"

  cd "$build_dir"
  if $YARN; then
    echo ""
    (yarn list --depth=0 || true) 2>/dev/null
    echo ""
  else
    (npm ls --depth=0 | tail -n +2 || true) 2>/dev/null
  fi
}

run_if_present() {
  local script_name=${1:-}
  local has_script=$(read_json "$BUILD_DIR/package.json" ".scripts[\"$script_name\"]")
  if [ -n "$has_script" ]; then
    if $YARN; then
      echo "Running $script_name (yarn)"
      yarn run "$script_name"
    else
      echo "Running $script_name"
      npm run "$script_name" --if-present
    fi
  fi
}

log_build_scripts() {
  local build=$(read_json "$BUILD_DIR/package.json" ".scripts[\"build\"]")
  local scalingo_prebuild=$(read_json "$BUILD_DIR/package.json" ".scripts[\"scalingo-prebuild\"]")
  local scalingo_postbuild=$(read_json "$BUILD_DIR/package.json" ".scripts[\"scalingo-postbuild\"]")
  local postinstall=$(read_json "$BUILD_DIR/package.json" ".scripts[\"scalingo-postbuild\"]")

  if [ -n "$build" ]; then
    mcount "scripts.build"

    if [ -z "$scalingo_postbuild" ]; then
      mcount "scripts.build-without-scalingo-postbuild"
    fi

    if [ -z "$postinstall" ]; then
      mcount "scripts.build-without-postinstall"
    fi

    if [ -z "$postinstall" ] && [ -z "$scalingo_postbuild" ]; then
      mcount "scripts.build-without-other-hooks"
    fi
  fi

  if [ -n "$postinstall" ]; then
    mcount "scripts.postinstall"

    if [ "$postinstall" == "npm run build" ] ||
       [ "$postinstall" == "yarn run build" ] ||
       [ "$postinstall" == "yarn build" ]; then
      mcount "scripts.postinstall-is-npm-build"
    fi

  fi

  if [ -n "$scalingo_prebuild" ]; then
    mcount "scripts.scalingo-prebuild"
  fi

  if [ -n "$scalingo_postbuild" ]; then
    mcount "scripts.scalingo-postbuild"

    if [ "$scalingo_postbuild" == "npm run build" ] ||
       [ "$scalingo_postbuild" == "yarn run build" ] ||
       [ "$scalingo_postbuild" == "yarn build" ]; then
      mcount "scripts.scalingo-postbuild-is-npm-build"
    fi
  fi

  if [ -n "$scalingo_postbuild" ] && [ -n "$build" ]; then
    mcount "scripts.build-and-scalingo-postbuild"

    if [ "$scalingo_postbuild" != "$build" ]; then
      mcount "scripts.different-build-and-scalingo-postbuild"
    fi
  fi
}

yarn_supports_frozen_lockfile() {
  local yarn_version="$(yarn --version)"
  # Yarn versions lower than 0.19 will crash if passed --frozen-lockfile
  if [[ "$yarn_version" =~ ^0\.(16|17|18).*$ ]]; then
    mcount "yarn.doesnt-support-frozen-lockfile"
    false
  else
    true
  fi
}

yarn_node_modules() {
  local build_dir=${1:-}

  echo "Installing node modules (yarn.lock)"
  cd "$build_dir"
  if yarn_supports_frozen_lockfile; then
    yarn install --frozen-lockfile --ignore-engines 2>&1
  else
    yarn install --pure-lockfile --ignore-engines 2>&1
  fi
}

npm_node_modules() {
  local build_dir=${1:-}

  if [ -e $build_dir/package.json ]; then
    cd $build_dir

    if [ -e $build_dir/package-lock.json ]; then
      echo "Installing node modules (package.json + package-lock)"
    elif [ -e $build_dir/npm-shrinkwrap.json ]; then
      echo "Installing node modules (package.json + shrinkwrap)"
    else
      echo "Installing node modules (package.json)"
    fi
    _install_preselected_modules
    npm install --unsafe-perm --userconfig $build_dir/.npmrc 2>&1
  else
    echo "Skipping (no package.json)"
  fi
}

_install_preselected_modules() {
  # Separe the modules names with '\n'
  preselected_modules="phantomjs"
  for module in $preselected_modules ; do
    out=$($JQ ".dependencies.${module}" < package.json)
    if [ "$out" != "null" ] ; then
      npm install --unsafe-perm --quiet --userconfig $build_dir/.npmrc $module 2>&1
    fi
  done
}

npm_rebuild() {
  local build_dir=${1:-}

  if [ -e $build_dir/package.json ]; then
    cd $build_dir
    echo "Rebuilding any native modules"
    npm rebuild 2>&1
    if [ -e $build_dir/npm-shrinkwrap.json ]; then
      echo "Installing any new modules (package.json + shrinkwrap)"
    else
      echo "Installing any new modules (package.json)"
    fi
    npm install --unsafe-perm --userconfig $build_dir/.npmrc 2>&1
  else
    echo "Skipping (no package.json)"
  fi
}
