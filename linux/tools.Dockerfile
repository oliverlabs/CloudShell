
# IMAGE_LOCATION refers to a Microsoft-internal container registry which stores a cached version
# of the image built from base.Dockerfile. If you are building this file outside Microsoft, you 
# won't be able to reach this location, but don't worry!

# To build yourself locally, override this location with a local image tag. See README.md for more detail

ARG IMAGE_LOCATION=cdpxb787066ec88f4e20ae65e42a858c42ca00.azurecr.io/official/azure/cloudshell:1.0.20220308.1.base.master.e4f39539

# Copy from base build
FROM ${IMAGE_LOCATION}

ENV NODE_OPTIONS=--tls-cipher-list='ECDHE-RSA-AES128-GCM-SHA256:!RC4'

# Install latest Azure CLI package. CLI team drops latest (pre-release) package here prior to public release
# We don't support using this location elsewhere - it may be removed or updated without notice
RUN tdnf install -y azure-cli

# Install any Azure CLI extensions that should be included by default.
RUN az extension add --system --name ai-examples -y
RUN az extension add --system --name ssh -y

# EY: get an error when we try to install this.
RUN az extension add --system --name azure-cli-ml -y

# Install kubectl
RUN az aks install-cli \
    && chmod +x /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubelogin

# Install terraform
RUN tdnf update -y && bash ./tdnfinstall.sh \
  terraform

# github CLI
RUN wget -O /etc/yum.repos.d/gh-cli.repo https://cli.github.com/packages/rpm/gh-cli.repo \
  && echo gpgcheck=0 >> /etc/yum.repos.d/gh-cli.repo \
  && tdnf repolist --refresh \
  && tdnf install -y gh.x86_64

RUN mkdir -p /usr/cloudshell
WORKDIR /usr/cloudshell

# Copy and run script to Install powershell modules and setup Powershell machine profile
COPY ./linux/powershell/PSCloudShellUtility/ /usr/local/share/powershell/Modules/PSCloudShellUtility/
COPY ./linux/powershell/ powershell
RUN /usr/bin/pwsh -File ./powershell/setupPowerShell.ps1 -image Top && rm -rf ./powershell

# install powershell warmup script
COPY ./linux/powershell/Invoke-PreparePowerShell.ps1 linux/powershell/Invoke-PreparePowerShell.ps1

# Install Office 365 CLI templates
RUN npm install -q -g @pnp/cli-microsoft365

# Install Bicep CLI
RUN curl -Lo bicep https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64 \
  && chmod +x ./bicep \
  && mv ./bicep /usr/local/bin/bicep \
  && bicep --help

# Remove su so users don't have su access by default. 
RUN rm -f ./linux/Dockerfile && rm -f /bin/su

# Temp: fix linkerd symlink if it points nowhere. This can be removed after next base image update
RUN ltarget=$(readlink /usr/local/linkerd/bin/linkerd) && \
    if [ ! -f $ltarget ] ; then rm /usr/local/linkerd/bin/linkerd ; ln -s /usr/local/linkerd/bin/linkerd-stable* /usr/local/linkerd/bin/linkerd ; fi

# Temp: fix ansible modules. Proper fix is to update base layer to use regular python for Ansible.
RUN wget -nv -q https://raw.githubusercontent.com/ansible-collections/azure/dev/requirements-azure.txt \
    && /opt/ansible/bin/python -m pip install -r requirements-azure.txt \
    && rm requirements-azure.txt

# Add user's home directories to PATH at the front so they can install tools which
# override defaults
# Add dotnet tools to PATH so users can install a tool using dotnet tools and can execute that command from any directory
ENV PATH ~/.local/bin:~/bin:~/.dotnet/tools:$PATH

# Set AZUREPS_HOST_ENVIRONMENT 
ENV AZUREPS_HOST_ENVIRONMENT cloud-shell/1.0