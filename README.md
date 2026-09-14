mkdir -p app-offline-install && cd app-offline-install && curl -L -O https://github.com/instacreatorx/sql-ai-agent-release/releases/download/v1.0.12-2/app-delivery-v1.0.12-2.zip  && curl -L -O  https://github.com/instacreatorx/sql-ai-agent-release/releases/download/v1.0.12-2/deploy-offline.sh  && chmod +x deploy-offline.sh && echo -e "\n\e[1;32m[SUCCESS]\e[
0m Folder created and both files downloaded."

./deploy-offline.sh --pass=xyz123
