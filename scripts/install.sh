#!/bin/bash
# Путь к локальному файлу java openjdk для установки на сервер
java_package_path="../files/openlogic-openjdk-11.0.18+10-linux-x64-deb.deb"

# Куда ставить java на удаленном сервере
remote_java_package_path="/tmp/openlogic-openjdk-11.0.18+10-linux-x64-deb.deb"


# Полные пути к файлам бэки дамаска и путь к скрипту для запуска
damask_sync_api_path="../files/damask_sync_api-1.0.jar"
damask_sh_path="../files/damask.sh"

# Переменные для файла damask.properties
jwt_pass="Xjyb87BvSjx7"
cert_pass="66OAI6nJetUH"
disk_pass="9I8qYY59SLvh"
node_addresses="10.0.0.155" # Приватные ip серверов astra
node_count=1 # Количество серверов в кластере

# Путь до файла с сервисом
service_file="../files/damask.service"

# Функция для вывода выделенного сообщения
highlight_message() {
    echo -e "\033[1;33m$1\033[0m"
}

configure_system_limits() {
 #   local server=$1
 #   local port=$2
 #   local remote_user=$3

    echo "Настройка системных лимитов и параметров"
    
 #   ssh -o StrictHostKeyChecking=no -i "$private_key_path" -p "$port" "astra@$server" <<'ENDSSH'
    
    sudo bash -c 'echo "fs.file-max = 922337203685470003" > /etc/sysctl.conf'
    sudo sysctl -p
    tst=$(whoami)
    echo $tst

    # Проверка и добавление лимитов в /etc/security/limits.conf
    limits_file="/etc/security/limits.conf"
    if ! sudo grep -q "^$tst " "$limits_file"; then
        echo -e "$tst soft nofile 500000\n$tst hard nofile 500000" | sudo tee -a "$limits_file" > /dev/null
        echo "Добавлены лимиты для пользователя $tst в $limits_file"
    else
        echo "Лимиты для пользователя $tst уже присутствуют в $limits_file"
    fi

    sudo sysctl -p
#ENDSSH

    highlight_message "Настройка системных лимитов и параметров завершена"
}

# Функция для проверки и создания директории, изменения владельца и назначения нужных пермишенов /opt/damask и /opt/data на удаленных серверах
check_create_damask_directory() {
#    local server=$1
#    local port=$2
#    local remote_user=$3
    echo "Проверка директории /opt/damask и /opt/data"
##    ssh -o StrictHostKeyChecking=no -i "$private_key_path" -p "$port" "astra@$server" 'bash -s' <<ENDSSH
    if [ ! -d "/opt/damask" ]; then
        echo "Директория /opt/damask не существует. Создание..."
        sudo mkdir -p /opt/damask
        sudo chown -R 'astra':astra /opt/damask
        sudo chmod 770 /opt/damask
    else
        echo "Директория /opt/damask уже существует."
    fi

    if [ ! -d "/opt/data" ]; then
        echo "Директория /opt/data не существует. Создание..."
        sudo mkdir -p /opt/data
        sudo chown -R 'astra':astra /opt/data
        sudo chmod 770 /opt/data
    else
        echo "Директория /opt/data уже существует."
    fi
#ENDSSH
    highlight_message "Проверка директорий /opt/damask и /opt/data завершена"
}


# Функция для проверки и установки Java 11 на удаленном сервере
check_java_remote() {
   # local server=$1
   # local port=$2
   # local remote_user=$3
    echo "Проверка Java"

#    ssh -o StrictHostKeyChecking=no -i "$private_key_path" -p "$port" "astra@$server" 'bash -s' <<ENDSSH
    echo "Выполнение команды на сервере \$(hostname)"
    if ! command -v java &> /dev/null; then
        echo "Java не установлена. Копирование и установка Java 11..."       
    else
        echo "Java уже установлена."
    fi
#ENDSSH

    if ! command -v java &> /dev/null;  then
        echo "Копирование файла"
        cp "$java_package_path" "$remote_java_package_path"
        
        echo "Установка Java 11"
      #  ssh -o StrictHostKeyChecking=no -i "$private_key_path" -p "$port" "astra@$server" 'bash -s' <<ENDSSH

        sudo bash -c '
        dpkg -i $remote_java_package_path
        apt-get install -f -y 
        sudo su
        sudo dpkg -i $remote_java_package_path
        sudo apt-get install -f -y 
        echo "Установка Java 11 завершена"
        '

#ENDSSH
    fi

    highlight_message "Проверка Java завершена"
}

# Функция для проверки и установки keytool на удаленном сервере
check_keytool_remote() {
    #local server=$1
    #local port=$2
    #local remote_user=$3
    #echo "Проверка keytool на сервере astra@$server"
   # ssh -o StrictHostKeyChecking=no -i "$private_key_path" -p "$port" "astra@$server" 'bash -s' <<'ENDSSH'
    echo "Выполнение команды"
    if ! command -v keytool &> /dev/null; then
        echo "keytool не установлен. Установка keytool..."
        sudo su
        sudo apt-get update
        sudo apt-get install -y default-jdk
    else
        echo "keytool уже установлен."
    fi
    echo "Выполнение команды завершено"
#ENDSSH
 #   highlight_message "Проверка keytool на сервере astra@$server завершена"
}

#check_java_remote
#check_keytool_remote 
configure_system_limits 
check_create_damask_directory 
# Генерация ключа для шифрования данных на диске в хранилище
keytool -genseckey -alias damask.master.key -keystore master.p12 -storetype PKCS12 -keyalg aes -storepass "$disk_pass" -keysize 256

# Генерация ключа для шифрования данных JWT токенов
keytool -genkey -dname "CN=test, OU=test, O=test, L=test, ST=test, C=test" -keyalg RSA -alias damask.oauth.jwt -keystore damask.p12 -storepass "$jwt_pass" -keypass "$jwt_pass"

# Генерация сертификатов и конфигурационных файлов для каждого узла
IFS=',' read -ra node_ips <<< "$node_addresses"
for i in "${!node_ips[@]}"; do
    node_name="Node$((i+1))"
    node_alias="$(echo "$node_name" | tr '[:upper:]' '[:lower:]')"

    # Генерация сертификата для текущего узла
    keytool -genkey -keystore "$node_alias.p12" -keyalg RSA -validity 365 -storepass "$cert_pass" -keypass "$cert_pass" -alias "$node_name" -dname "CN=$node_name" -storetype pkcs12

    # Экспорт публичного сертификата из сгенерированного файла
    keytool -export -alias "$node_name" -keystore "$node_alias.p12" -file "$node_name.cer" -storepass "$cert_pass"
done
copy_files() {
    #local server=$1
    #local port=$2
    #local remote_user=$3
    shift 3
    local files=("$@")

    echo "Копирование файлов на сервер astra@$server"

    for file in "${files[@]}"; do
        local filename=$(basename "$file")
        local remote_path="/opt/damask/$filename"

        if [[ "$filename" == "damask$node_index.properties" ]]; then
            new_filename="damask.properties"
            remote_path="/opt/damask/$new_filename"
            echo "Копирование файла $file как $new_filename на сервер astra@$server"
        fi

        # Копирование файла на сервер
        cp  "$file" "$remote_path"

        # Изменение владельца и прав на файл
        sudo chown astra:damask $remote_path"
        sudo chmod 770 $remote_path"
    done

    echo "Копирование файлов завершено"
}


copy_optional_files() {
   # local servers=("${!1}")
   # local ports=("${!2}")
   # local users=("${!3}")
   cp ../files/damask.properties /opt/damask
   cp *p12 /opt/damask
   cp *cer /opt/damask
    local files_to_copy=("$damask_sh_path" "$damask_sync_api_path")

    

    #for i in "${!servers[@]}"; do
        #server=${servers[$i]}
        #port=${ports[$i]}
        #user=${users[$i]}
#
        #echo "Проверка на сервере astra@$server"
        #
        #ssh -o StrictHostKeyChecking=no -i "$private_key_path" -p "$port" "$user@$server" 'bash -s' <<ENDSSH

#ENDSSH

        for file in "${files_to_copy[@]}"; do
      #      if ! ssh -o StrictHostKeyChecking=no -i "$private_key_path" -p "$port" "$user@$server" "[[ -e /opt/damask/$(basename $file) ]]"; then

                cp "$file" "/opt/damask/"
            
                # Изменение владельца и прав доступа после копирования
                echo "Изменение владельца и прав доступа для файла $(basename $file)"
             #   ssh -o StrictHostKeyChecking=no -i "$private_key_path" -p "$port" "$user@$server" <<EOF
                sudo chown $user:$user "/opt/damask/$(basename $file)"
                sudo chmod 770 "/opt/damask/$(basename $file)"
#EOF
       #     else
        #        echo "Файл $(basename $file) уже присутствует. Пропуск копирования."
          #  fi
        done
  #  done

    echo "Копирование дополнительных файлов завершено"
}

copy_service_file() {
  #  local servers=("${!1}")
  #  local ports=("${!2}")
  #  local users=>("${!3}")

    echo "Копирование файла damask.service в директорию /tmp"

    #for i in "${!servers[@]}"; do
    #    server=${servers[$i]}
    #    port=${ports[$i]}
    #    user=${users[$i]}
        echo "Копирование файла damask.service"
        cp "$service_file" /tmp/damask.service
        echo "Копирование файла damask.service завершено"
    #done
}

# Вызов функции с передачей массивов
copy_service_file #servers[@] ports[@] users[@]


# Копирование файлов на все серверы
#for i in "${!servers[@]}"; do
#    server=${servers[$i]}
#    port=${ports[$i]}
#    user=${users[$i]
# Вызов функции для копирования файлов на все сервера
# Вызов функции с передачей массивов
copy_optional_files ##servers[@] ports[@] users[@]

