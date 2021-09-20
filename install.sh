 wget https://npm.taobao.org/mirrors/node/v8.0.0/node-v8.0.0-linux-x64.tar.xz
 tar xvf node-v8.0.0-linux-x64.tar.xz 
 vim /etc/profile
 export NODE_HOME=/usr/local/node  
 export PATH=$NODE_HOME/bin:$PATH
 
 mv node-v8.0.0-linux-x64 /usr/local/node
 source /etc/profile
 npm -v
 npm get registry 
 npm config set registry http://registry.npm.taobao.org/
 npm install gitbook-cli -g
 yum install epel-release
 yum install nginx
 gitbook init
 gitbook serve 
 
 
 
 
 扩展：  
 /var/run/yum.pid 已被锁定，PID 为 98081 的另一个程序正在运行。
 解决方案：
 rm -rf /var/run/yum.pid
