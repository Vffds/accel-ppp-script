#!/bin/bash
# Скрипт для установки accel-ppp на Debian 10

# Остановить скрипт при возникновении ошибки в любой из команд
set -e

# Обновляю список пакетов
apt update

# Устанавливаю то, что нужно для компиляции и запуска
apt install -y build-essential cmake gcc git libpcre3-dev libssl-dev liblua5.1-0-dev linux-headers-amd64

# Клонирую репозиторий проекта
git clone https://github.com/accel-ppp/accel-ppp.git /opt/accel-ppp-code

# Создаю каталог для сборки
mkdir /opt/accel-ppp-code/build

# Перехожу в него
cd /opt/accel-ppp-code/build/

# Конфигурирую с опциями по-умолчанию
cmake -DBUILD_IPOE_DRIVER=TRUE -DBUILD_VLAN_MON_DRIVER=TRUE -DCMAKE_INSTALL_PREFIX=/usr -DKDIR=/usr/src/linux-headers-`uname -r` -DLUA=TRUE -DCPACK_TYPE=Debian10 ..

# При компиляции будет жаловаться, что нет каталога /usr/src/linux-headers-4.19.0-23-amd64
# Обманываем систему. Делаю ссылку на аналог
ln -s /usr/src/linux-headers-4.19.0-27-amd64 /usr/src/linux-headers-4.19.0-23-amd64

# Компилирую
make

# Делаю пакет для Дебиан
cpack -G DEB

# Устанавливаю его
dpkg -i accel-ppp.deb

# Переименовываю конфигурационный файл
mv /etc/accel-ppp.conf.dist /etc/accel-ppp.conf

# Выключаю радиус
sed -i 's/#radius/radius/' /etc/accel-ppp.conf

# Включаю локальные учётки
sed -i 's/#chap-secrets/chap-secrets/' /etc/accel-ppp.conf

# Разрешаю подключаться всем из интернетов
sed -i 's/10.0.0.0\/8/0.0.0.0\/0/' /etc/accel-ppp.conf

# Ставлю Goole DNS
sed -i '/\[dns\]/a dns1=8.8.8.8\ndns2=8.8.4.4' /etc/accel-ppp.conf

# Создаю учётки
generate_password() {
    < /dev/urandom tr -dc A-Za-z0-9 | head -c 8
}

echo "#client     server      secret      ip-address      speed" > /etc/ppp/chap-secrets

for i in {01..10}; do
    user="user${i}"
    password=$(generate_password)
    echo "$user     *           $password   *" >> /etc/ppp/chap-secrets
done

# Запускаю как системный юнит
systemctl start accel-ppp

# Добавляю в автозагрузку
systemctl enable accel-ppp

# Нужно включить нат на сервере, чтобы выпускать клиентов с него в инет
sed -i '/^#net.ipv4.ip_forward=1/c\net.ipv4.ip_forward=1' /etc/sysctl.conf

# Применить изменения
sysctl -p

# Создаю скрипт, который будет настраивать файрвол — выпускать абонов в инет
cat << 'EOF' | tee /etc/iptables.sh > /dev/null
#!/bin/sh
iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
iptables -A FORWARD -i ppp0 -o ens3 -j ACCEPT
iptables -A FORWARD -i ens3 -o ppp0 -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

# Делаю скрипт исполняемым
chmod +x /etc/iptables.sh

# Запускаю его, применяю правила файрвола
/etc/iptables.sh

# Добавляю его в автозагрузку
cat << 'EOF' | tee /etc/rc.local > /dev/null
#!/bin/sh -e
/etc/iptables.sh
exit 0
EOF

# Делаю его исполняемым
chmod +x /etc/rc.local

# Добавляю в автозапуск
systemctl enable rc-local

# Вывожу логины-пароли:
cat /etc/ppp/chap-secrets | awk '{print $1, $3}'
