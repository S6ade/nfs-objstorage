# Ansible: Пошаговая настройка NFS

Это **пошаговое руководство** по превращению двух чистых виртуальных машин (созданных, например, через Terraform) в работающий NFS-сервер и NFS-клиент с помощью Ansible.

---

## 📋 Что мы сделаем
1. Подготовим окружение Ansible для подключения к серверам.
2. Напишем роль `nfs_server` для хоста, который будет раздавать директорию.
3. Напишем роль `nfs_client` для хоста, который будет эту директорию монтировать.
4. Создадим общий плейбук, запустим его и протестируем синхронизацию файлов.

---

## 🛠️ Шаг 1. Подготовка Ansible

### 1.1. Настройка `ansible.cfg`
Чтобы Ansible не запрашивал подтверждение SSH-ключей при первом подключении, создайте в папке `ansible/` файл **`ansible.cfg`**:

```ini
[defaults]
host_key_checking = False
roles_path = ./roles
```
> **Зачем это нужно:** `roles_path` указывает Ansible искать кастомные роли непосредственно в локальной папке `roles/`, а не в системных директориях.

### 1.2. Настройка `inventory.ini`
Скопируйте шаблон инвентаря и впишите актуальные IP-адреса ваших виртуальных машин:

```bash
cp inventory.example.ini inventory.ini
nano inventory.ini
```

Приведите файл к следующему виду:

```ini
[nfs_serv]
nfs-serv ansible_host=51.250.33.223 ansible_user=s6ade

[nfs_client]
nfs-client ansible_host=158.160.166.205 ansible_user=s6ade

[all:vars]
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_python_interpreter=/usr/bin/python3
```
> ⚠️ **Важно:** Замените IP-адреса на свои. Имя пользователя (`ansible_user`) должно соответствовать созданному вами пользователю (например, заданному через `cloud-init`).

### 1.3. Проверка связи
Убедитесь, что Ansible успешно дотягивается до обоих хостов:

```bash
ansible all -i inventory.ini -m ping
```
*Оба хоста должны вернуть статус `SUCCESS`.*

---

## 📝 Шаг 2. Создание роли для сервера (`nfs_server`)

### 2.1. Переменные по умолчанию (`roles/nfs_server/defaults/main.yml`)
```yaml
---
nfs_share_dir: /srv/share/nfs
nfs_client_subnet: "192.168.10.0/24"  # Подсеть, которой разрешен доступ
nfs_options: "rw,sync,no_subtree_check"
```
> **Зачем это нужно:** Избегаем хардкода путей и сетевых настроек внутри тасок, чтобы конфигурацию можно было менять в одном файле.

### 2.2. Шаблон конфигурации (`roles/nfs_server/templates/exports.j2`)
Создайте Jinja2-шаблон, состоящий из одной строки:

```jinja
{{ nfs_share_dir }} {{ nfs_client_subnet }}({{ nfs_options }})
```
> **Зачем это нужно:** Ansible подставит объявленные переменные и сгенерирует рабочий конфигурационный файл `/etc/exports` на целевом сервере.

### 2.3. Задачи роли (`roles/nfs_server/tasks/main.yml`)
```yaml
---
- name: Обновить кэш пакетов
  apt:
    update_cache: yes
    cache_valid_time: 3600

- name: Установить NFS-сервер
  apt:
    name: nfs-kernel-server
    state: present

- name: Создать папку для раздачи
  file:
    path: "{{ nfs_share_dir }}"
    state: directory
    mode: '0777'

- name: Скопировать конфиг экспорта
  template:
    src: exports.j2
    dest: /etc/exports
  notify: Restart nfs

- name: Применить экспорт директорий
  command: exportfs -a
  changed_when: false

- name: Запустить и включить службу NFS
  systemd:
    name: nfs-kernel-server
    state: started
    enabled: yes
```
> 💡 **Обратите внимание:**
> * `mode: '0777'` позволяет клиентам без проблем записывать файлы в общую папку.
> * `notify: Restart nfs` — если шаблон `exports` изменится, сработает хендлер перезапуска.
> * `command: exportfs -a` — обязательный шаг, без которого ядро сервера не узнает о новой доступной папке.

### 2.4. Обработчики событий (`roles/nfs_server/handlers/main.yml`)
```yaml
---
- name: Restart nfs
  service:
    name: nfs-kernel-server
    state: restarted
```
> ⚠️ **Важно:** Имя хендлера (`name`) должно символ в символ совпадать со строкой, указанной в `notify` внутри задач (регистрозависимо).

---

## 📝 Шаг 3. Создание роли для клиента (`nfs_client`)

### 3.1. Переменные по умолчанию (`roles/nfs_client/defaults/main.yml`)
```yaml
---
nfs_server_ip: "51.250.33.223"  # ВАЖНО: Укажите здесь IP вашего NFS-сервера!
nfs_remote_path: "/srv/share/nfs"
nfs_mount_point: "/mnt/share"
```

### 3.2. Задачи роли (`roles/nfs_client/tasks/main.yml`)
```yaml
---
- name: Обновить кэш пакетов
  apt:
    update_cache: yes
    cache_valid_time: 3600

- name: Установить NFS-клиент
  apt:
    name: nfs-common
    state: present

- name: Создать точку монтирования
  file:
    path: "{{ nfs_mount_point }}"
    state: directory

- name: Смонтировать сетевую папку с сервера
  ansible.posix.mount:
    path: "{{ nfs_mount_point }}"
    src: "{{ nfs_server_ip }}:{{ nfs_remote_path }}"
    fstype: nfs
    state: mounted
```
> 💡 **Обратите внимание:** Параметр `state: mounted` не только монтирует директорию прямо сейчас, но и автоматически прописывает постоянную запись в `/etc/fstab`, чтобы папка успешно монтировалась сама после перезагрузки клиента.

---

## 🚀 Шаг 4. Запуск Playbook

Создайте главный файл сценария (например, `playbooks/nfs.yml`) и подключите туда роли:

```yaml
---
- name: Настройка NFS Сервера
  hosts: nfs_serv
  become: yes
  roles:
    - nfs_server

- name: Настройка NFS Клиента
  hosts: nfs_client
  become: yes
  roles:
    - nfs_client
```

Запустите выполнение плейбука из папки `ansible/`:

```bash
ansible-book -i inventory.ini playbooks/nfs.yml
```

**Что произойдет в процессе:**
1. Ansible зайдет на сервер, установит пакеты, создаст директорию, перенесет шаблон конфига, применит экспорт и запустит службу NFS.
2. Ansible переключится на клиент, установит `nfs-common`, подготовит точку монтирования и свяжет её с сервером через `/etc/fstab`.
3. В конце выполнения вы должны увидеть `PLAY RECAP` со значением `failed=0`.

---

## 🧪 Шаг 5. Проверка работы

1. Подключитесь по SSH к **клиенту** и создайте тестовый файл:
   ```bash
   touch /mnt/share/test.txt
   ```
2. Подключитесь по SSH к **серверу** и проверьте содержимое папки раздачи:
   ```bash
   ls -l /srv/share/nfs/
   ```

*Если вы видите файл `test.txt` на сервере — поздравляем, ваша NFS-сеть успешно настроена и работает!*

---

## ⚠️ Возможные проблемы и их решение

* **`The requested handler 'restart nfs' was not found`**
  Проверьте регистр букв и пробелы. Имя в `notify` (в задачах сервера) должно в точности совпадать с `name` в `handlers/main.yml`.
* **`Failed to resolve server`**
  Вы забыли заполнить переменную `nfs_server_ip` в файле переменных клиента `roles/nfs_client/defaults/main.yml`.
* **`access denied by server`**
  На сервере не была применена конфигурация шаринга. Убедитесь, что отработал шаг `exportfs -a` или выполните эту команду на сервере вручную.
