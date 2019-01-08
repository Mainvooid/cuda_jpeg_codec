#include "main.h"

using namespace cv;
using namespace std;
using namespace jpeg_common;

//int main(int argc, char* argv[])
//{
//	// 创建命令行解析器
//	cmdline::parser m_parser;
//	/*
//	添加参数
//	长名称,短名称(\0表示没有短名称),参数描写,是否必须,默认值.
//	cmdline::range()限制范围,cmdline::oneof<>()限制可选值.
//	通过调用不带类型的add方法,定义bool值(通过调用exsit()方法来推断).
//	*/
//	m_parser.add<std::string>("input_fname", 'i', "input jpeg file name.", true, "4K.jpg");
//	m_parser.add<std::string>("output_fname", 'o', "output jpeg file name.", true, "4K_gen.jpg");
//	m_parser.add<int>("width", 'w', "jpeg width.", true, 4096);
//	m_parser.add<int>("height", 'h', "jpeg height.", true, 4096);
//	m_parser.add<int>("channel", 'c', "jpeg channel.", true, 3);
//	m_parser.add<int>("quality", 'q', "jpeg encode quality.", true, 30);
//
//	//执行解析
//	m_parser.parse_check(argc, argv);
//
//	// 获取输入的參数值
//	std::string input_fname = m_parser.get<std::string>("input_fname");
//	std::string output_fname = m_parser.get<std::string>("output_fname");
//	int width = m_parser.get<int>("width");
//	int height = m_parser.get<int>("height");
//	int channel = m_parser.get<int>("channel");
//	int quality = m_parser.get<int>("quality");
//
//	cv::Mat src = cv::imread(input_fname);
//	cvtColor(src, src, cv::COLOR_BGR2YUV_I420);
//}


int main(int argc, char **argv)
{
	//测试数据YUVI420
	//std::string input_fname = "../data/4K.jpg";
	//std::string output_fname = "../data/4K_gen.jpg";

	std::string input_fname = "../data/1080P.jpg";
	std::string output_fname = "../data/1080P_gen.jpg";

	cv::Mat src = cv::imread(input_fname);
	cv::cvtColor(src, src, cv::COLOR_BGR2YUV_I420);

	//cv::namedWindow("src", cv::WindowFlags::WINDOW_NORMAL);
	//cv::resizeWindow("src",cv::Size(1024,1536));
	//cv::imshow("src", src);
	//waitKey(0);

	//初始化编码器(宽高通道编码质量) 目前还未独立支持单通道编码,而是在3通道图像上通过UV分量置128来实现灰度编码.
	//CudaJpegEncoder encoder= CudaJpegEncoder(4096, 4096, 3, 90);
	CudaJpegEncoder encoder = CudaJpegEncoder(1920, 1080, 3, 90);

	//传YUV主机数据
	encoder.setData(src.data, PixelFormat::PIX_FMT_YUVI420);

	//编码
	encoder.EncodeJpeg();

	//写文件,编码数据指针encoder.pDstJpeg,长度encoder.nOutputLenth
	jpeg_common::WriteJpeg(output_fname, encoder.pDstJpeg, encoder.nOutputLenth);
}

