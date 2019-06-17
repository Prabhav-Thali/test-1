FROM node:10.16.0

#VOLUME /node-red/node-red
RUN git clone --depth=50 https://github.com/node-red/node-red.git /node-red/node-red \
    && cd /node-red/node-red/ \
    && git checkout 0.20.5 \
    && npm install 2>&1 | tee build.log \
    && npm install -g istanbul coveralls \
    && npm run build \
    && npm test  2>&1 | tee test.log \
    && mkdir artifacts && mv build.log test.log ./artifacts 

#VOLUME /node-red/node-red
#EXPOSE 1880
WORKDIR /node-red/node-red
CMD ["bash"]
