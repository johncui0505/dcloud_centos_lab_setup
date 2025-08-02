#!/bin/bash

# This script automates the installation of Python 3.11 with SSL support
# and the latest Ansible on CentOS 7.

echo "Starting installation process..."

# Remove any Ansible installed via yum
echo "Attempting to remove any existing yum-installed Ansible..."
sudo yum remove ansible -y

# Configure CentOS-Base.repo to point to vault.centos.org for consistency
echo "Configuring yum repositories to vault.centos.org/7.9.2009..."
sudo tee /etc/yum.repos.d/CentOS-Base.repo > /dev/null << 'EOF'
[base]
name=CentOS-7 - Base
baseurl=http://vault.centos.org/7.9.2009/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

[updates]
name=CentOS-7 - Updates
baseurl=http://vault.centos.org/7.9.2009/updates/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

[extras]
name=CentOS-7 - Extras
baseurl=http://vault.centos.org/7.9.2009/extras/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1
EOF

# Clean and make yum cache
echo "Cleaning and rebuilding yum cache..."
sudo yum clean all
sudo yum makecache

# Final yum update after repo configuration
echo "Running final yum update after repository configuration..."
sudo yum update -y

# Install Core Development Tools and Dependencies
echo "Installing development tools and dependencies..."
sudo yum groupinstall "Development Tools" -y
sudo yum install -y wget zlib-devel bzip2-devel openssl-devel libffi-devel \
    ncurses-devel sqlite-devel readline-devel tk-devel gdbm-devel xz-devel \
    perl-core pcre-devel

# --- 2. Install OpenSSL 1.1.1w from Source (Required for Python 3.11 SSL) ---
echo "2. Installing OpenSSL 1.1.1w from source..."
OPENSSL_VERSION="1.1.1w"
OPENSSL_DIR="/usr/local/openssl${OPENSSL_VERSION//./}" # e.g., /usr/local/openssl111w

cd /usr/local/src || { echo "Failed to change directory to /usr/local/src"; exit 1; }

# Download and extract OpenSSL
if [ ! -f "openssl-${OPENSSL_VERSION}.tar.gz" ]; then
    echo "Downloading OpenSSL ${OPENSSL_VERSION}..."
    sudo wget "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
fi
sudo tar -xzf "openssl-${OPENSSL_VERSION}.tar.gz"
cd "openssl-${OPENSSL_VERSION}" || { echo "Failed to change directory to openssl-${OPENSSL_VERSION}"; exit 1; }

# Configure, compile, and install OpenSSL to a custom location
echo "Configuring and compiling OpenSSL..."
sudo ./config --prefix="${OPENSSL_DIR}" --openssldir="${OPENSSL_DIR}" shared zlib
sudo make -j$(nproc) # Use all available CPU cores for faster compilation
sudo make install

# Add OpenSSL library path to dynamic linker configuration
echo "${OPENSSL_DIR}/lib" | sudo tee /etc/ld.so.conf.d/openssl${OPENSSL_VERSION//./}.conf
sudo ldconfig

echo "OpenSSL ${OPENSSL_VERSION} installed to ${OPENSSL_DIR}"

# --- 3. Install Python 3.11.11 from Source ---
echo "3. Installing Python 3.11.11 from source..."
PYTHON_VERSION="3.11.11"
PYTHON_SOURCE_DIR="/usr/src/Python-${PYTHON_VERSION}"

cd /usr/src || { echo "Failed to change directory to /usr/src"; exit 1; }

# Download and extract Python
if [ ! -f "Python-${PYTHON_VERSION}.tgz" ]; then
    echo "Downloading Python ${PYTHON_VERSION}..."
    sudo wget "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
fi
sudo tar xzf "Python-${PYTHON_VERSION}.tgz"
cd "Python-${PYTHON_VERSION}" || { echo "Failed to change directory to Python-${PYTHON_VERSION}"; exit 1; }

# Clean up previous build artifacts if any
sudo make clean

# Configure Python with explicit OpenSSL paths and shared libraries
echo "Configuring and compiling Python ${PYTHON_VERSION}..."
sudo ./configure --enable-shared \
    --with-openssl="${OPENSSL_DIR}" \
    --with-openssl-rpath=auto \
    --enable-loadable-sqlite-extensions \
    --prefix=/usr/local \
    LDFLAGS="-L${OPENSSL_DIR}/lib" \
    CPPFLAGS="-I${OPENSSL_DIR}/include"

sudo make -j$(nproc) # Use all available CPU cores for faster compilation
sudo make altinstall

# Add Python's shared library path to dynamic linker configuration
echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/python${PYTHON_VERSION%.*}.conf # e.g., python3.11.conf
sudo ldconfig

echo "Python ${PYTHON_VERSION} installed to /usr/local/bin/python${PYTHON_VERSION%.*}"

# --- 4. Verify Python 3.11 and SSL Module ---
echo "4. Verifying Python 3.11 and SSL module..."
if command -v python${PYTHON_VERSION%.*} &> /dev/null; then
    echo "Python ${PYTHON_VERSION} version:"
    python${PYTHON_VERSION%.*} --version

    echo "Python ${PYTHON_VERSION} SSL module check:"
    python${PYTHON_VERSION%.*} -c "import ssl; print(ssl.OPENSSL_VERSION)"
else
    echo "Error: python${PYTHON_VERSION%.*} command not found. Python installation might have failed."
    exit 1
fi

# --- 5. Install Latest Ansible using Python 3.11's pip ---
echo "5. Installing latest Ansible using pip for Python ${PYTHON_VERSION}..."
PIP_CMD="/usr/local/bin/pip${PYTHON_VERSION%.*}"

if [ -f "${PIP_CMD}" ]; then
    sudo "${PIP_CMD}" install ansible
else
    echo "Error: ${PIP_CMD} not found. pip for Python ${PYTHON_VERSION} might not be installed correctly."
    exit 1
fi

# --- 6. Verify Ansible Installation ---
echo "6. Verifying Ansible installation..."
if command -v ansible &> /dev/null; then
    ansible --version
else
    echo "Error: Ansible command not found. Ansible installation might have failed."
    exit 1
fi

echo "Installation complete. Python ${PYTHON_VERSION} and Ansible are now installed."
echo "You can run 'ansible --version' to confirm."