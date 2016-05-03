#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <semaphore.h>

#include <cuda_runtime.h>


//const int DATA_N = 10000000;
const int DATA_N = 100;


void* gpu_monitor(void* arg);
__global__ void add(int* a, int n);

sem_t localGPU_TaskSizeSubmit_sem;     
sem_t localGPU_TaskSubmit_sem;         
sem_t localGPU_beginComputation_sem;   
sem_t localGPU_computationFin_sem;

typedef struct
{
    //Host-side input data and computation result,if computation is not int summary,typedef sth substitute int
    int taskNo;
	int result;
	void *ptBegin;   	//reserved   raw data poniter(if taskNo > 4     malloc)
	int *ptSize;		//reserved   raw data size poniter(if taskNo > 4     malloc)
    void *begin[4];  	//initial container for raw data pointer
	int size[4];		//initial container for raw data size pointer; in bytes
}	GPUTask;

GPUTask gpuTask;

int main()
{
	int res;
    pthread_t gpu_thread;
    void *thread_result;

	res = sem_init(&localGPU_TaskSizeSubmit_sem, 0, 0);
	if(res != 0)
	{
		perror("sem localGPU_TaskSubmit_sem initialization failed");
		exit(EXIT_FAILURE);
	}

	res = sem_init(&localGPU_TaskSubmit_sem, 0, 0);
	if(res != 0)
	{
		perror("sem localGPU_TaskSubmit_sem initialization failed");
		exit(EXIT_FAILURE);
	}
	res = sem_init(&localGPU_beginComputation_sem, 0, 0);
	if(res != 0)
	{
	perror("sem localGPU_beginComputation_sem initialization failed");
	exit(EXIT_FAILURE);
	}
	res = sem_init(&localGPU_computationFin_sem, 0, 0);
	if(res != 0)
	{
		perror("sem localGPU_computationFin_sem initialization failed");
		exit(EXIT_FAILURE);
	}
	res = pthread_create(&gpu_thread, NULL, gpu_monitor, NULL);
	if (res != 0)
	{
		perror("Thread creation failed");
		exit(EXIT_FAILURE);
	}

	//gpuTask.taskNo = 4;
	gpuTask.taskNo = 1;
	int i, j;
	
	for(i = 0; i < gpuTask.taskNo; i++)
	{
		gpuTask.size[i] = DATA_N * sizeof(int);
	}

	sem_post(&localGPU_TaskSizeSubmit_sem);

	sem_wait(&localGPU_TaskSubmit_sem);

	int * intArray;
	int cpuSum = 0;
	for(i = 0;i < gpuTask.taskNo; i++)
	{
		intArray = (int *)gpuTask.begin[i];
		//ÆäÊµÕâÀïÓ¦¸ÃÅÐ¶ÏDATA_N*sizeof(int)ÊÇ²»ÊÇÓësize[i]ÏàµÈ~
		for(j = 0; j < DATA_N; j++)
			cpuSum += intArray[j] = j;
	}
	sem_post(&localGPU_beginComputation_sem);
	sem_wait(&localGPU_computationFin_sem);
	printf("The sum of gpu is %d\n",gpuTask.result);
	printf("The sum of cpu is %d\n",cpuSum);

    res = pthread_join(gpu_thread, &thread_result);
    if (res != 0) {
        perror("Thread join failed");
        exit(EXIT_FAILURE);
    }
    printf("Thread joined\n");
 
	sem_destroy(&localGPU_TaskSizeSubmit_sem);
	sem_destroy(&localGPU_TaskSubmit_sem);
	sem_destroy(&localGPU_beginComputation_sem);
	sem_destroy(&localGPU_computationFin_sem);
    exit(EXIT_SUCCESS);	

	return 0;
}

void *gpu_monitor(void *arg) {
	sem_wait(&localGPU_TaskSizeSubmit_sem);  // P²Ù×÷
	
	//int GPU_num = 0;
	//cudaGetDeviceCount(&GPU_num);
	//printf("The count of GPU is %d\n", GPU_num);	
	
	int i;
	int* mission; //data on gpu

	for(i = 0; i < gpuTask.taskNo; i++)
	{
		gpuTask.begin[i] = malloc(gpuTask.size[i]);
		cudaSetDevice(2);
		cudaMalloc((void**)&mission, gpuTask.size[i]);
		//cudaMemcpy(mission[i], &intArray[0], gpuTask.size[i], cudaMemcpyHostToDevice);
		printf("GPU %d cudaMalloc success.\n", i);
	}
	sem_post(&localGPU_TaskSubmit_sem);   // V²Ù×÷
	
	sem_wait(&localGPU_beginComputation_sem);	
	
	int* intArray;
	int sumGPUs = 0;
	int* sum;
	for(i = 0; i < gpuTask.taskNo; i++)
	{
		//sum = 0;
		intArray = (int *)gpuTask.begin[i];
		//cudaSetDevice(i);
		cudaMemcpy(mission, &intArray[0], gpuTask.size[i], cudaMemcpyHostToDevice);
		printf("cudaMemcpy success.\n");
		add<<<1, 2>>>(mission, DATA_N);
		//for(j = 0; j < DATA_N; j++)
			//sum += intArray[j];
		cudaMemcpy(sum, mission, sizeof(int), cudaMemcpyDeviceToHost);
		sumGPUs += sum[0];
		printf("ok\n");
		printf("sum: %d\n", sum[0]);
	}
	gpuTask.result = sumGPUs;
	sem_post(&localGPU_computationFin_sem);
}

__global__ void add(int* a, int n)
{
	int i = threadIdx.x+blockDim.x+blockIdx.x;

	for(i = 1; i < n; i++)
	{
		a[0] += a[i];
	}
}
