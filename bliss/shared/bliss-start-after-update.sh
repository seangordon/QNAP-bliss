CONF=/etc/config/qpkg.conf
QPKG_NAME="bliss"
INSTALL_PATH=$(/sbin/getcfg $QPKG_NAME Install_Path -d "" -f $CONF)
"${INSTALL_PATH}"/bliss-runner.sh start

