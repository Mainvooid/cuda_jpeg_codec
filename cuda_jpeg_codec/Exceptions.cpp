#include "Exceptions.h"

//对Exceptions.h中的声明进行定义
namespace npp {
	std::ostream &
	operator << (std::ostream &rOutputStream, const npp::Exception &rException)
	{
		rOutputStream << rException.toString();
		return rOutputStream;
	}
}