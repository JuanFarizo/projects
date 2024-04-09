FROM node

WORKDIR /app

COPY package.json /app

RUN npm install

COPY . /app

#Expose certain port to the localsystem
EXPOSE 80 

CMD ["node", "server.js"]