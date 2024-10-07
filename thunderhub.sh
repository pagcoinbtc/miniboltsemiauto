#!/bin/bash

# Script criado por PagcoinBTC
# PGP: 9585 831e 06ac 0821
# Ultima edição: 07/10/2024

GITHUB_CRIPTOSHARK=https://github.com/cryptosharks131/lndg.git
LNDG_DIR=/home/admin/lndg
VERSION_THUB=0.13.31
read -sp "Digite a senha para ThunderHub: " senha
echo

# Atualiza os pacotes do sistema
sudo apt update && sudo apt full-upgrade -y

# Criar link simbólico para a configuração
if [ ! -f /etc/nginx/sites-enabled/thunderhub-reverse-proxy.conf ]; then
  sudo ln -s /etc/nginx/sites-available/thunderhub-reverse-proxy.conf /etc/nginx/sites-enabled/
fi

# Testar a configuração do NGINX
sudo nginx -t
if [ $? -ne 0 ]; then
  echo "Erro na configuração do NGINX. Verifique o arquivo de configuração."
  exit 1
fi

# Recarregar a configuração do NGINX
sudo systemctl reload nginx

# Configurar o firewall para permitir tráfego na porta 4002
sudo ufw allow 4002/tcp comment 'allow ThunderHub SSL from anywhere'

# Verifica se os pré-requisitos estão instalados
node -v
npm -v

# Volta ao diretório home
cd

# Importa a chave GPG do repositório do ThunderHub
curl https://github.com/apotdevin.gpg | gpg --import

# Clona o repositório do ThunderHub na versão especificada e entra no diretório
git clone --branch v$VERSION_THUB https://github.com/apotdevin/thunderhub.git && cd thunderhub

# Verifica a integridade do commit
git verify-commit v$VERSION_THUB

# Atualiza os pacotes do sistema
sudo apt update && sudo apt full-upgrade -y

# Instala as dependências do ThunderHub
npm install

# Executa a build do ThunderHub
npm run build

# Verifica a versão instalada no package.json
head -n 3 /home/admin/thunderhub/package.json | grep version

# Copiar o modelo do ficheiro de configuração
cp .env .env.local

# Editar a linha 51 do arquivo .env.local para incluir a configuração desejada
# Usando sed para substituir a linha 51
sed -i '51s|.*|ACCOUNT_CONFIG_PATH="/home/admin/thunderhub/thubConfig.yaml"|' .env.local

# Cria a configuração da conta
# Criar um novo arquivo thubConfig.yaml

# Criar ou sobrescrever o arquivo thubConfig.yaml com o conteúdo inicial
cat <<EOL > thubConfig.yaml
masterPassword: 'PASSWORD'
accounts:
  - name: 'MiniBolt'
    serverUrl: '127.0.0.1:10009'
    macaroonPath: '/data/lnd/data/chain/bitcoin/mainnet/admin.macaroon'
    certificatePath: '/data/lnd/tls.cert'
    password: '[E] ThunderHub password'
EOL

# Usar sed para substituir a senha na linha 7
# Procurar pela palavra "[E] ThunderHub password" e substituir pela senha fornecida
sed -i "7s|\[E\] ThunderHub password|$senha|" thubConfig.yaml

# Cria o serviço systemd para o ThunderHub
sudo bash -c 'cat <<EOF > /etc/systemd/system/thunderhub.service
# MiniBolt: systemd unit for Thunderhub
# /etc/systemd/system/thunderhub.service

[Unit]
Description=ThunderHub
Requires=lnd.service
After=lnd.service

[Service]
WorkingDirectory=/home/admin/thunderhub
ExecStart=/usr/bin/npm run start

User=admin

# Process management
####################
TimeoutSec=300

# Hardening Measures
####################
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF'

# Habilita o serviço para iniciar com o sistema e o inicia
sudo systemctl enable thunderhub
sudo systemctl start thunderhub

# Verifica o status do serviço ThunderHub
sudo systemctl status thunderhub

# Atualiza os pacotes do sistema
sudo apt update && sudo apt full-upgrade -y

# Verifica se o git está instalado, caso contrário, instala
if ! command -v git &> /dev/null
then
    echo "Git não encontrado, instalando..."
    sudo apt install git -y
fi

# Volta à home
cd

# Clona o repositório, se ainda não estiver clonado
if [ ! -d "$LNDG_DIR" ]; then
    git clone $GITHUB_CRIPTOSHARK && cd lndg
else
    echo "O repositório já foi clonado."
    cd lndg
fi

# Instala o virtualenv (ou python3-venv) se não estiver instalado
if ! command -v virtualenv &> /dev/null
then
    echo "Instalando virtualenv..."
    sudo apt install virtualenv -y
fi

# Configura o ambiente virtual
virtualenv -p python3 .venv

# Ativa o ambiente virtual e instala as dependências
source .venv/bin/activate
pip install -r requirements.txt
pip install whitenoise

# Executa o script de inicialização
.venv/bin/python initialize.py --whitenoise

# Cria o service para o backend
sudo tee /etc/systemd/system/lndg-controller.service > /dev/null <<EOF
[Unit]
Description=Controlador de backend para Lndg

[Service]
Environment=PYTHONUNBUFFERED=1
User=admin
Group=admin
ExecStart=$LNDG_DIR/.venv/bin/python $LNDG_DIR/controller.py
StandardOutput=append:/var/log/lndg-controller.log
StandardError=append:/var/log/lndg-controller.log
Restart=always
RestartSec=60s

[Install]
WantedBy=multi-user.target
EOF

# Cria o service para o frontend
sudo tee /etc/systemd/system/lndg.service > /dev/null <<EOF
[Unit]
Description=LNDG Django Server
After=network.target

[Service]
Environment=PYTHONUNBUFFERED=1
User=admin
Group=admin
WorkingDirectory=$LNDG_DIR
ExecStart=$LNDG_DIR/.venv/bin/python $LNDG_DIR/manage.py runserver 0.0.0.0:8889
StandardOutput=append:/var/log/lndg.log
StandardError=append:/var/log/lndg.log
Restart=always
RestartSec=5
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF

# Recarrega e reinicia os serviços
sudo systemctl daemon-reload
sudo systemctl restart lndg-controller.service
sudo systemctl restart lndg.service

# Mostra o status dos serviços
sudo systemctl status lndg-controller.service
sudo systemctl status lndg.service
