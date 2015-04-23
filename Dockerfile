FROM google/nodejs:0.10.32

ADD . /kudobot
WORKDIR /kudobot

RUN npm install --production

CMD ["npm", "start"]
