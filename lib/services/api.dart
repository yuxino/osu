import "dart:io";
import "dart:convert";

// c1 is code one
// c2 is code two
getConversion({String c1, String c2}) async {
  try {
    final url =
        "http://www.zhaotool.com/v1/api/huobi/e10adc3949ba59abbe56e057f20f883e/$c2/$c1";
    final httpClient = HttpClient();
    final request = await httpClient.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode == HttpStatus.OK) {
      final json = await response.transform(utf8.decoder).join();
      final data = jsonDecode(json);
      return data;
    } else {
      throw "Error getting IP address: ${request.uri}\n"
          "Http status ${response.statusCode}";
    }
  } catch (exception) {
    throw exception;
  }
}
