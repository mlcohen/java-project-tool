JAVA_PROJECT_TOOL_VERSION="0.0.1"

JARS_LIB_DIR=~/lib/java/jars
MAVEN_REPO_BASE_URL=https://repo1.maven.org/maven2/

PROJECT_CONFIG_FILE_NAME="project.json"
PROJECT_CONFIG_DEFAULT_JAVA_SOURCE_DIR="src/main/java"
PROJECT_CONFIG_DEFAULT_JAVA_RESOURCE_DIR="src/main/resources"
PROJECT_CONFIG_DEFAULT_JAVA_BUILD_DIR="build"

JAR_DEPENDENCY_ENTRY_DEFAULT_SCOPE="implementation"
JAR_DEPENDENCY_ENTRY_PARAM_INDEX_GROUP_ID=0
JAR_DEPENDENCY_ENTRY_PARAM_INDEX_ARTIFACT_ID=1
JAR_DEPENDENCY_ENTRY_PARAM_INDEX_VERSION=2
JAR_DEPENDENCY_ENTRY_PARAM_INDEX_SCOPE=3

JAVA_PROJECT_CONFIG_TEMPLATE=""
IFS='' read -r -d '' JAVA_PROJECT_CONFIG_TEMPLATE <<"EOF"
{
  "sourceDirectory": "{{SOURCE_DIR}}",
  "resourcesDirectory": "{{RESOURCES_DIR}}",
  "buildDirectory": "{{BUILD_DIR}}",
  "dependencies": []
}
EOF

function jar_dependency_entry__parse()
{
  local entry_parts=($(column -s ':' -t <<< $1))
  local group_id=${entry_parts[$JAR_DEPENDENCY_ENTRY_PARAM_INDEX_GROUP_ID]}
  local artifact_id=${entry_parts[$JAR_DEPENDENCY_ENTRY_PARAM_INDEX_ARTIFACT_ID]}
  local version=${entry_parts[$JAR_DEPENDENCY_ENTRY_PARAM_INDEX_VERSION]}
  local scope=${entry_parts[$JAR_DEPENDENCY_ENTRY_PARAM_INDEX_SCOPE]:-$JAR_DEPENDENCY_ENTRY_DEFAULT_SCOPE}
  echo $group_id $artifact_id $version $scope
}

function jar_dependency_entry__get_group_id()
{
  local value=($(jar_dependency_entry__parse $1))
  echo ${value[$JAR_DEPENDENCY_ENTRY_PARAM_INDEX_GROUP_ID]}
}

function jar_dependency_entry__get_artifact_id()
{
  local value=($(jar_dependency_entry__parse $1))
  echo ${value[$JAR_DEPENDENCY_ENTRY_PARAM_INDEX_ARTIFACT_ID]}
}

function jar_dependency_entry__get_version()
{
  local value=($(jar_dependency_entry__parse $1))
  echo ${value[$JAR_DEPENDENCY_ENTRY_PARAM_INDEX_VERSION]}
}

function jar_dependency_entry__get_scope()
{
  local value=($(jar_dependency_entry__parse $1))
  echo ${value[$JAR_DEPENDENCY_ENTRY_PARAM_INDEX_SCOPE]}
}

function jar_dependency_entry__to_base_path()
{
  local group_id=$(jar_dependency_entry__get_group_id $1)
  local artifact_id=$(jar_dependency_entry__get_artifact_id $1)
  local version=$(jar_dependency_entry__get_version $1)
  echo "$(sed 's/\./\//g' <<< $group_id)/$artifact_id/$version"
}

function jar_dependency_entry__to_absolute_path()
{
  local basepath=$(jar_dependency_entry__to_base_path $1)
  echo "$JARS_LIB_DIR/$basepath"
}

function jar_dependency_entry__to_remote_jar_file_name()
{
  local artifact_id=$(jar_dependency_entry__get_artifact_id $1)
  local version=$(jar_dependency_entry__get_version $1)
  echo "$artifact_id-$version.jar"
}

function jar_dependency_entry__to_maven_repo_url()
{
  local jar_base_path=$(jar_dependency_entry__to_base_path $1)
  local remote_jar_file_name=$(jar_dependency_entry__to_remote_jar_file_name $1)
  local remote_jar_url="$MAVEN_REPO_BASE_URL$jar_base_path/$remote_jar_file_name"
  echo $remote_jar_url
}

function jar_dependency_entry__is_jar_loaded()
{
  local jar_abspath=$(jar_dependency_entry__to_absolute_path $1)

  if [ ! -d "$jar_abspath" ]; then
    return 1
  fi

  local jar_files=($(find $jar_abspath -name '*.jar'))

  if [ ${#jar_files[@]} -eq 0 ]; then
    return 1
  fi
}

function project_config__get_json_content()
{
  cat $PROJECT_CONFIG_FILE_NAME
}

function project_config__get_java_source_directory()
{
  local value=$(jq -r '. | (
    if .sourceDirectory == null then "" else .sourceDirectory end
  )' $PROJECT_CONFIG_FILE_NAME)
  echo "${value:-$PROJECT_CONFIG_DEFAULT_JAVA_SOURCE_DIR}"
}

function project_config__get_java_resource_directory()
{
  local value=$(jq -r '. | (
    if .resourceDirectory == null then "" else .resourceDirectory end
  )' $PROJECT_CONFIG_FILE_NAME)
  echo "${value:-$PROJECT_CONFIG_DEFAULT_JAVA_RESOURCE_DIR}"
}

function project_config__get_java_build_directory()
{
  local value=$(jq -r '. | (
    if .buildDirectory == null then "" else .buildDirectory end
  )' $PROJECT_CONFIG_FILE_NAME)
  echo "${value:-$PROJECT_CONFIG_DEFAULT_JAVA_BUILD_DIR}"
}

function project_config__get_main_classname()
{
  local value=$(jq -r '. | (
    if .mainClassname == null then "" else .mainClassname end
  )' $PROJECT_CONFIG_FILE_NAME)
  echo "$value"
}

function project_config__get_jar_dependency_entries()
{
  local flag_param_key=${1%=*}     # get everything before =
  local flag_param_value=${1#--*=} # get everything after =
  local flag_scope="all"
    
  if [ "$flag_param_key" == "--scope" ] && [ -n "$flag_param_value" ]; then
    flag_scope=$flag_param_value
  fi

  local content=$(project_config__get_json_content)
  local jar_dependency_entries=($(jq -r '.dependencies[]
    | (
      if .id == null then
        "\(.groupId):\(.artifactId):\(.version)" + (
          if .scope == null then "" else ":" + .scope end
        )
      else
        .id
      end
    )' $PROJECT_CONFIG_FILE_NAME))
  local result_exit_code=$?
  
  if [ $result_exit_code -ne 0 ]; then
    return 1
  fi

  local jar_dep_entry=""

  for jar_dep_entry in ${jar_dependency_entries[@]}; do
    local jar_dep_entry_scope=$(jar_dependency_entry__get_scope $jar_dep_entry)

    if [ "$flag_scope" == "all" ] || [ "$flag_scope" == "$jar_dep_entry_scope" ]; then
      echo $jar_dep_entry
    fi
  done
}

function project_config__has_jar_dependency_entry()
{
  local jar_dep_entries=($(project_config__get_jar_dependency_entries))
  local jar_dep_entry=""

  for jar_dep_entry in ${jar_dep_entries[@]}; do
    if [ "$1" == "$jar_dep_entry" ]; then
      return 0
    fi
  done

  return 1
}

function build_classpath_from_jar_dependency_entries()
{
  local entry_flag_param=$1
  local jar_path_entries=()
  local jar_dep_entry=""

  for jar_file_entry in $(project_config__get_jar_dependency_entries $entry_flag_param); do
    local dirpath=$(jar_dependency_entry__to_absolute_path $jar_file_entry)
    local jar_files=($(find $dirpath -name '*.jar'))
    jar_path_entries=("${jar_path_entries[@]}" "${jar_files[0]}")
  done

  echo $(sed 's/ /:/g' <<< "${jar_path_entries[@]}")
}

function load_jar_dependency()
{
  local jar_dep_entry=$1

  if jar_dependency_entry__is_jar_loaded $jar_dep_entry; then
    return 0
  fi

  local jar_remote_url=$(jar_dependency_entry__to_maven_repo_url $jar_dep_entry)
  local head_response=$(curl "$jar_remote_url" -I -s -w '%{http_code}')
  local response_status_code=$(tail -1 <<< "$head_response")

  printf "loading $jar_dep_entry... "

  if [ "$response_status_code" != "200" ]; then
    local exit_code=0

    case "$response_status_code" in
      "404" ) exit_code=1 ;;
      "000" ) exit_code=2 ;;
      * ) exit_code=3 ;;
    esac

    echo "failed ($exit_code)" 

    return $exit_code
  fi

  local jar_base_path=$(jar_dependency_entry__to_base_path $1)

  pushd $JARS_LIB_DIR > /dev/null
  mkdir -p $jar_base_path
  pushd $jar_base_path > /dev/null

  find . -name '*.jar' -exec rm '{}' +
  curl "$jar_remote_url" -O -s
  
  popd > /dev/null
  popd > /dev/null

  echo done
}

function load_all_jar_dependencies()
{
  local load_jar_failures=0
  local jar_dep_entry=""

  for jar_dep_entry in $(project_config__get_jar_dependency_entries --scope=all); do
    load_jar_dependency $jar_dep_entry
    local load_result=$?
    if [ load_result -ne 0 ]; then
      load_jar_failures=1
    fi
  done

  if [ $load_jar_failures -gt 0 ]; then
    return 1
  fi
}

function build_project()
{
  load_all_jar_dependencies

  local load_jars_result=$?

  if [ $load_jars_result -ne 0 ]; then
    echo "Error: Cannot build. Unable to load all required jars" >&2
    return 1
  fi

  local classpath="${BUILD_DIR}:$(build_classpath_from_jar_dependency_entries --scope=all)"
  local processorpath="$(build_classpath_from_jar_dependency_entries --scope=annotation)"
  local src_dir=$(project_config__get_java_source_directory)
  local build_dir=$(project_config__get_java_build_directory)
  local resource_dir=$(project_config__get_java_resource_directory)
  local src_files=($(find $src_dir -name '*.java'))

  if [ -z "$processorpath" ]; then
    javac -cp $classpath -d $build_dir ${src_files[@]}
  else
    javac -cp $classpath --processor-path $processorpath -d $build_dir ${src_files[@]}
  fi

  cp -R ${resource_dir}/ $build_dir
}

function add_dependencies()
{
  local json=$(project_config__get_json_content)
  local jar_dep_entry=""
  local added_entries=()

  for jar_dep_entry in $@; do
    if project_config__has_jar_dependency_entry $jar_dep_entry; then
      continue
    fi

    local parsed_entry=($(jar_dependency_entry__parse $jar_dep_entry))
    local groupId=${parsed_entry[JAR_DEPENDENCY_ENTRY_PARAM_INDEX_GROUP_ID]}
    local artifactId=${parsed_entry[JAR_DEPENDENCY_ENTRY_PARAM_INDEX_ARTIFACT_ID]}
    local version=${parsed_entry[JAR_DEPENDENCY_ENTRY_PARAM_INDEX_VERSION]}
    local scope=${parsed_entry[JAR_DEPENDENCY_ENTRY_PARAM_INDEX_SCOPE]}
    local new_json_dep_entry="groupId: \"$groupId\", artifactId: \"$artifactId\", version: \"$version\""

    if [ "$scope" != "$JAR_DEPENDENCY_ENTRY_DEFAULT_SCOPE" ]; then
      new_json_dep_entry="$new_json_dep_entry, scope: \"$scope\""
    fi

    local jq_statement=".dependencies |= . + [{ $new_json_dep_entry }]"

    json=$(jq "$jq_statement" <<< "$json")

    added_entries=("${added_entries[@]}" "$jar_dep_entry")
  done

  cat <<JSON > $PROJECT_CONFIG_FILE_NAME
$json
JSON

  local added_entry=""

  for added_entry in ${added_entries[@]}; do
    load_jar_dependency $added_entry
  done
}

function init_project()
{
  local template="$JAVA_PROJECT_CONFIG_TEMPLATE"

  template=$(sed "s|{{SOURCE_DIR}}|$PROJECT_CONFIG_DEFAULT_JAVA_SOURCE_DIR|" <<< "$template")
  template=$(sed "s|{{RESOURCES_DIR}}|$PROJECT_CONFIG_DEFAULT_JAVA_RESOURCE_DIR|" <<< "$template")
  template=$(sed "s|{{BUILD_DIR}}|$PROJECT_CONFIG_DEFAULT_JAVA_BUILD_DIR|" <<< "$template")

  mkdir -p $PROJECT_CONFIG_DEFAULT_JAVA_SOURCE_DIR
  mkdir -p $PROJECT_CONFIG_DEFAULT_JAVA_RESOURCE_DIR

  printf "$template\n" > $PROJECT_CONFIG_FILE_NAME
}

function clean()
{
  local build_dir=$(project_config__get_java_build_directory)
  rm -rf "$build_dir"
}

function run_app() 
{
  local main_classname=$(project_config__get_main_classname)
  local build_dir=$(project_config__get_java_build_directory)
  local classpath="${build_dir}:$(build_classpath_from_jar_dependency_entries --scope=implementation)"
  java -cp $classpath "$main_classname" "$@"
}

function run()
{
  clean
  build_project
  run_app "$@"
}

function print_tool_version()
{
  echo "Java Project Tool (JPT) v$JAVA_PROJECT_TOOL_VERSION"
}

COMMAND=$1

shift

case "$COMMAND" in
  "build" ) build_project ;;
  "clean" ) clean ;;
  "app" ) run_app "$@" ;;
  "run" ) run ;;
  "add" ) add_dependencies "$@" ;;
  "init" ) init_project "$@" ;;
  "version" ) print_tool_version ;;
  * )
    echo invalid command $COMMAND
    exit 1
    ;;
esac
