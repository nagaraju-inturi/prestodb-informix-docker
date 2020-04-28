docker stop prestodb
docker rm prestodb
docker ps -a -q | xargs -n 1 -I {} docker rm {}
#docker rmi $( docker images | grep '<none>' | tr -s ' ' | cut -d ' ' -f 3)
docker volume rm $(docker volume ls -qf dangling=true)
cd ./server_ctx
docker build -t prestodb/informix .
#docker run  --privileged  -v /sys/fs/cgroup:/sys/fs/cgroup -d -h informix --name prestodb -p 64210:64210 -p 8090:8090 prestodb/informix --start
docker run  --privileged -d -h informix --name prestodb -p 64210:64210 -p 8090:8090 prestodb/informix --start
docker exec -it prestodb bash
