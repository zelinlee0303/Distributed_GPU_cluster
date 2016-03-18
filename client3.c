#include <sys/types.h>
#include <sys/socket.h>
#include <stdio.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <stdlib.h>

int main() {
  int sockfd;
  int len;
  struct sockaddr_in address;
  int result;
  char ch = '1';

  sockfd = socket(AF_INET, SOCK_STREAM, 0);

  address.sin_family = AF_INET;
  address.sin_addr.s_addr = inet_addr("127.0.0.1");
  address.sin_port = htons(9734);
  len = sizeof(address);

  result = connect(sockfd, (struct sockaddr *)&address, len);

  if(result == -1) {
    perror("oops:client3");
    exit(1);
  }

  float num_c = 6.5;
  float num_c_r;
  num_c_r = num_c + 1.5;

  write(sockfd, &ch, 1);
  read(sockfd, &ch, 1);
  if(ch =='2')
    ;
  else{
    perror("wrong");
    exit(1);
  }

  write(sockfd, &num_c_r, 8);
  
  
  close(sockfd);
  exit(0);
}
